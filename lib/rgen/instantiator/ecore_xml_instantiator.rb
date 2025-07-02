require 'rgen/ecore/ecore'
require 'rgen/instantiator/abstract_xml_instantiator'
require 'rgen/array_extensions'

class ECoreXMLInstantiator < AbstractXMLInstantiator

  include RGen::ECore

  INFO = 0
  WARN = 1
  ERROR = 2

  def initialize(env, loglevel=ERROR)
    @env = env
    @ecoreFileName = ""
    @rolestack = []
    @elementstack = []
    @element_by_id = {}
    @loglevel = loglevel
  end

  def start_tag(prefix, tag, namespaces, attributes)
    eRef = nil
    if @elementstack.last
      eRef = eAllReferences(@elementstack.last).find{|r|r.name == tag}
      if eRef
        if attributes["xsi:type"] && attributes["xsi:type"] =~ /ecore:(\w+)/
          class_name = $1
          attributes.delete("xsi:type")
        else
          class_name = eRef.eType.name
        end
      else
        raise "Reference not found: #{tag} on #{@elementstack.last}"
      end
    else
      class_name = tag
    end

    eClass = RGen::ECore.ecore.eClassifiers.find{|c| c.name == class_name}
    if eClass
      obj = RGen::ECore.const_get(class_name).new
      if attributes["xmi:id"]
        @element_by_id[attributes["xmi:id"]] = obj
        attributes.delete("xmi:id")
      end
      if eRef
        if eRef.many
          @elementstack.last.addGeneric(eRef.name, obj)
        else
          @elementstack.last.setGeneric(eRef.name, obj)
        end
      end
      @env << obj
      @elementstack.push obj
    else
      log WARN, "Class not found: #{class_name}"
      @elementstack.push nil
    end

    attributes.each_pair do |attr, value|
      set_attribute_internal(attr, value)
    end
  end

  def end_tag(prefix, tag)
    @elementstack.pop
  end

  ResolverDescription = Struct.new(:object, :attribute, :value)

  def set_attribute(attr, value)
    # do nothing, already handled by start_tag/set_attribute_internal
  end

  def set_attribute_internal(attr, value)
    return unless @elementstack.last
    eFeat = eAllStructuralFeatures(@elementstack.last).find{|a| a.name == attr}
    if eFeat.is_a?(EReference)
      rd = ResolverDescription.new
      rd.object = @elementstack.last
      rd.attribute = attr
      rd.value = value
      @resolver_descs << rd
    elsif eFeat
      value = true if value == "true" && eFeat.eType == EBoolean
      value = false if value == "false" && eFeat.eType == EBoolean
      value = value.to_i if eFeat.eType == EInt || eFeat.eType == ELong
      value = value.to_f if eFeat.eType == EFloat || eFeat.eType == EDouble
      value = Date.parse(value) if eFeat.eType == EDate
      @elementstack.last.setGeneric(attr, value)
    else
      log WARN, "Feature not found: #{attr} on #{@elementstack.last}"
    end
  end

  def instantiate(name, file)
    @resolver_descs = []
#    puts "Instantiating ..."
    super(file.read, 1000)
    rp = @env.rootPackage(name)
    @env.resourceAdd(name, File.basename(file.path), rp&.nsURI, rp)
    @ecoreFileName = File.basename(file.path)

#    puts "Resolving ..."
    @resolver_descs.each do |rd|
      refed = find_referenced(rd.value)
      raise StandardError.new("Reference not found for: #{rd.attribute}: #{rd.value}") if refed.empty?
      feature = eAllStructuralFeatures(rd.object).find{|f| f.name == rd.attribute}
      raise StandardError.new("StructuralFeature not found: #{rd.attribute}") unless feature
      if feature.many
        rd.object.setGeneric(feature.name, refed)
      else
        rd.object.setGeneric(feature.name, refed.first)
      end
    end
  end

  def eAllReferences(element)
    @eAllReferences ||= {}
    @eAllReferences[element.class] ||= element.class.ecore.eAllReferences
  end

  def eAllAttributes(element)
    @eAllAttributes ||= {}
    @eAllAttributes[element.class] ||= element.class.ecore.eAllAttributes
  end

  def eAllStructuralFeatures(element)
    @eAllStructuralFeatures ||= {}
    @eAllStructuralFeatures[element.class] ||= element.class.ecore.eAllStructuralFeatures
  end

  # context is an array of packages
  def find_referenced(desc)
    def builtin_types(str)
      case str
        when "EString";     RGen::ECore::EString
        when "EInt";        RGen::ECore::EInt
        when "ELong";       RGen::ECore::ELong
        when "EBoolean";    RGen::ECore::EBoolean
        when "EFloat";      RGen::ECore::EFloat
        when "EDouble";     RGen::ECore::EDouble
        when "EDate";       RGen::ECore::EDate
        when "EObject";     RGen::ECore::EObject
        when "EJavaObject"; RGen::ECore::EJavaObject
        when "EJavaClass";  RGen::ECore::EJavaClass
        else raise StandardError.new("No translation for '#{str}'")
      end
    end

    match = desc.scan(/(?:ecore:([\w]*)\s)?([^\s]*)?#\/\d*\/([\w\/]+)/)
    if match
      # match is a nested array
      match.collect do |m|
        type = m[0]
        uri = m[1]
        object = m[2]

        if type == "EDataType" && !uri.nil? && uri == "http://www.eclipse.org/emf/2002/Ecore"
            builtin_types(object)
        else
          ctx = @env.contextFor(uri, @ecoreFileName)
          raise StandardError.new("No suitable context found for '#{uri}'") if ctx.nil?
          find_in_context(ctx, object.split('/'))
        end
      end

    elsif desc.match(/^#([^\/]+)$/)
      # This is matched when xmi:id is used
      @element_by_id[$1]

    else
      raise "Could not find reference for '#{desc}'"
    end.compact
  end

  def find_in_context(context, desc_elements)
    if context.is_a?(EPackage)
      r = (context.eClassifiers + context.eSubpackages).find{|c| c.name == desc_elements.first}
    elsif context.is_a?(EClass)
      r = context.eStructuralFeatures.find{|s| s.name == desc_elements.first}
    else
      raise StandardError.new("Don't know how to find #{desc_elements.join('/')} in context '#{context.name}' (#{context})")
    end
    if r
      if desc_elements.size > 1
        find_in_context(r, desc_elements[1..-1])
      else
        r
      end
    else
      log WARN, "Can not follow path, element #{desc_elements.first} not found within #{context}(#{context.name})"
    end
  end

  def log(level, msg)
    puts %w(INFO WARN ERROR)[level] + ": " + msg if level >= @loglevel
  end
end
