require 'rgen/instantiator/ecore_uri_fragment_resolver'
require 'rgen/instantiator/nodebased_xml_instantiator'
module RGen

module Instantiator

class IdentitiyUriFragmentMapper
  def map(original_uri_fragment)
    original_uri_fragment
  end
end

class EcoreModelXmlInstantiator < NodebasedXMLInstantiator
  include Util::NameHelper
  include RGen::ECore

  NamespaceDescriptor = Struct.new(:prefix, :target_name, :target)
  UnresolvedReference = Struct.new(:object, :feature_name, :index)

  INFO = 0
  WARN = 1
  ERROR = 2

  # The uri_fragment_mapper serves the possibility to manipulate the
  # uri_fragments of object references, when you parse only a sub tree
  # of a original ecore model xml file, before the instantiator tries to
  # resolve the references inside the model.
  def initialize(env, meta_models, uri_fragment_mapper = IdentitiyUriFragmentMapper.new, loglevel=INFO)
    super(env)
    @uri_fragment_mapper = uri_fragment_mapper
    @loglevel = loglevel
    @default_meta_model = meta_models.first
    @tag_ns_map = {}
    @unresolvedReferences = []
    @object_by_xmi_id = {}
    @object_by_ecore_id = {}
    @efeature_cache = {}
    meta_models.each{|mm| add_meta_model(mm)}
  end

  def on_descent(node)
    parent_efeature = nil
    # Ignore root XMI container node
    return if node.tag == "xmi:XMI" && node.parent.nil?
    unless node.parent.nil? || node.parent.tag == "xmi:XMI"
      parent_efeature = get_efeature_by_name(node.parent.object.class, node.tag)
      if parent_efeature.nil?
        raise "Class '#{node.parent.object.class.name}' has no structual feature named '#{node.tag}'"
      end
    end

    if parent_efeature.nil? || parent_efeature.class <= EReference
      if node.attributes["href"].nil?
        node.object = create_typed_object(node, parent_efeature)
        return if node.object.nil?
        @env << node.object
        if node.attributes["xmi:id"]
          @object_by_xmi_id[node.attributes["xmi:id"]] = node.object
          node.attributes.delete("xmi:id")
        end
        node.attributes.each_pair { |k,v| set_feature(node, k, v) }
      else
        node.object = create_proxy_for_href(node)
      end
    else parent_efeature.class
      # Nothing to do here. Node is an EAttribute node, but chardata is not
      # set yet. On ascent the attribute value will be set on object of parent
      # node.
    end
  end

  def on_ascent(node)
    # Ignore root XMI container node
    return if node.tag == "xmi:XMI" && node.parent.nil?
    if node.object.nil? # EAttribute node
      node.chardata.each{ |value|
        set_feature(node.parent, node.tag, value)
      }
    else # Object node
      node.children.each { |c| assoc_parent_with_child(node, c) }
    end
  end

  def create_typed_object(node, parent_ereference)
    ns_desc = nil
    class_name = node.attributes["xsi:type"]
    node.attributes.delete("xsi:type")
    if !class_name.nil? && class_name != ""
      xsi_type_parts = class_name.split(":")
      if xsi_type_parts.length > 2
        raise "'#{class_name}' is not a valid xsi:type."
      end
      class_name = xsi_type_parts.last
      if xsi_type_parts.length > 1
        ns_desc = @tag_ns_map[xsi_type_parts.first]
      end
    elsif not parent_ereference.nil?
      type = parent_ereference.eType
      ns_desc = @tag_ns_map[type.ePackage.nsPrefix]
      class_name = type.name
    else
      ns_desc = @tag_ns_map[node.prefix]
      class_name = saneClassName(ns_desc.nil? ? node.qtag : node.tag)
    end
    model = (ns_desc && ns_desc.target) || @default_meta_model
    return model.const_get(class_name).new
  end

  def assoc_parent_with_child(parent, child)
    return unless parent.object && child.object
    eRef = parent.object.class.ecore.eAllReferences.find{|r| r.name == child.tag}
    if eRef.nil?
      raise "Class '#{parent.object.class.name}'' has no reference named '#{child.name}''"
    end
    if eRef.many
      parent.object.addGeneric(eRef.name, child.object)
    else
      parent.object.setGeneric(eRef.name, child.object)
    end
  end

  def set_feature(node, feature_name, value)
    eFeat = get_efeature_by_name(node.object&.class, feature_name)
    method_name = saneMethodName(feature_name)
    if eFeat.is_a?(EReference)
      if eFeat.getContainment
        raise "Can not set containment reference #{feature_name} at #{node.object.class.name} by ids."
      end
      if eFeat.many
        value.split(" ").each{ |identifier|
          proxy = RGen::MetamodelBuilder::MMProxy.new(identifier)
          @unresolvedReferences << UnresolvedReference.new(node.object, feature_name, node.object.send(feature_name).length)
          node.object.addGeneric(method_name, proxy)
        }
      else
        proxy = RGen::MetamodelBuilder::MMProxy.new(value)
        @unresolvedReferences << UnresolvedReference.new(node.object, feature_name, nil)
        node.object.setGeneric(method_name, proxy)
      end
    elsif not eFeat.nil?
      value = true if value == "true" && eFeat.eType == EBoolean
      value = false if value == "false" && eFeat.eType == EBoolean
      value = value.to_i if eFeat.eType == EInt || eFeat.eType == ELong
      value = value.to_f if eFeat.eType == EFloat || eFeat.eType == EDouble
      value = value.to_sym if eFeat.eType.is_a?(EEnum)
      value = Date.parse(value) if eFeat.eType == EDate
      if eFeat.many
        node.object.addGeneric(method_name, value)
      else
        node.object.setGeneric(method_name, value)
      end
      if eFeat.iD
        @object_by_ecore_id[value] = node.object
      end
    end
  end

  private

  def create_proxy_for_href(node)
    node.object = RGen::MetamodelBuilder::MMProxy.new(
      node.attributes["href"],
      is_external: true,
      attributes: node.attributes.select {|key, value|
        key != "href" && !key.start_with?("xsi:")
      }
    )
  end

  def get_efeature_by_name(type, name)
    return nil if type.nil?
    efeature = @efeature_cache[type]&.[](name)
    if efeature.nil?
      efeature = type.ecore.eAllStructuralFeatures.find{
        |f| f.name == name
      }
      unless efeature.nil?
        @efeature_cache[type] ||= {}
        @efeature_cache[type][name] = efeature
      end
    end
    return efeature
  end

  def add_meta_model(meta_model)
    if not meta_model.ecore.class <= EPackage
      raise ArgumentError.new("Only meta models supported which ecore class type is RGen::ECore::EPackage")
    end
    @tag_ns_map[meta_model.ecore.nsPrefix] = NamespaceDescriptor.new(meta_model.ecore.nsPrefix, meta_model.name, meta_model)
    meta_model.ecore.eSubpackages.each { |sp|
      add_meta_model(meta_model.const_get(sp.name))
    }
  end

  def resolve
    resolver = EcoreUriFragmentResolver
    @unresolvedReferences.each{ |uref|
      feature = uref.object.send(uref.feature_name)
      feature = feature[uref.index] unless uref.index.nil?
      # when using n:m references feature can already be resolved by opposite
      next unless feature.class <= RGen::MetamodelBuilder::MMProxy
      ref = @object_by_xmi_id[feature.targetIdentifier]
      if ref.nil?
        ref = @object_by_ecore_id[feature.targetIdentifier]
      end
      if ref.nil?
        uri_fragment = @uri_fragment_mapper.map(feature.targetIdentifier)
        ref = resolver.get_object_relative_to(uref.object, uri_fragment)
      end
      method_name = saneMethodName(uref.feature_name)
      if ref.nil?
        feature.data ||= {}
        feature.data[:rolver_info] = "Target could not be resolved."
      elsif uref.index.nil?
        uref.object.setGeneric(method_name, ref)
      else
        uref.object.removeGeneric(method_name, feature)
        uref.object.addGeneric(method_name, ref, uref.index)
      end
    }
    @unresolvedReferences = []
  end

end

end

end
