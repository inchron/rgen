require 'rgen/serializer/xml_serializer'
require 'cgi'

module RGen

module Serializer

class XMI20Serializer < XMLSerializer

  # rootElement is a root element of a ruby RGen::MetamodelBuilder::MMBase model tree
  # configuration is a hash containing
  # :prolog - 2D array of attribute tuples
  # :refStringFormat - Ordered array of "id", "path", "name", omissions possible.
  # :refStringPathFormat - String "name" or "index"
  def serialize(rootElement, configuration={})
    @referenceStrings = {}
    @configuration = configuration
    @idAttribute = rootElement.class.ecore.eAllAttributes.find{|att| att.iD}&.name
    buildReferenceStrings(rootElement, "#/", "/")
    addBuiltinReferenceStrings
    attrs = attributeValues(rootElement)
    attrs << ['xmi:version', "2.0"]
    attrs << ['xmlns:xmi', "http://www.omg.org/XMI"]
    attrs << ['xmlns:xsi', "http://www.w3.org/2001/XMLSchema-instance"]
    unless rootElement.class.ecore.ePackage.nsPrefix
      attrs << ['xmlns:ecore', "http://www.eclipse.org/emf/2002/Ecore" ]
    end
    for ns in gatherNamespaces(rootElement)
      attrs << ns unless ns.empty?
    end
    ns = rootElement.class.ecore.ePackage.nsPrefix || "ecore"
    tag = "#{ns}:#{rootElement.class.ecore.name}"

    prolog(@configuration[:prolog]) if @configuration.key?(:prolog)
    startTag(tag, attrs)
    writeComposites(rootElement)
    endTag(tag)
  end

  def writeComposites(element)
    eachReferencedElement(element, containmentReferences(element)) do |r,te|
      next unless te
      attrs = attributeValues(te)
      ns = te.class.ecore.ePackage.nsPrefix || "ecore"
      attrs << ['xsi:type', "#{ns}:#{te.class.ecore.name}"]
      tag = r.name
      startTag(tag, attrs)
      writeComposites(te)
      endTag(tag)
    end
  end

  def attributeValues(element)
    result = []
    return result unless element
    eAllAttributes(element).select{|a| !a.derived}.each do |a|
      val = element.getGeneric(a.name)
      val = CGI.escapeHTML(val) if val.is_a? String
       result << [a.name, val] unless val.nil? || val == ""
    end
    eAllReferences(element).select{|r| !r.containment && !(r.eOpposite && r.eOpposite.containment) && !r.derived}.each do |r|
      targetElements = element.getGenericAsArray(r.name)
      val = targetElements.collect{|te| getReferenceString(te)}.compact.join(' ')
      val = CGI.escapeHTML(val) if val.is_a? String
      result << [r.name, val] unless val.nil? || val == ""
    end
    result
  end

  # Build references for tree elements
  # Stores a name-based reference (default), an id (if an id attribute is
  # defined), and an xpath-like reference string
  def buildReferenceStrings(element, preName, prePath)
    return unless element
    refs = {
      :name => preName,
      :id => (element.send(@idAttribute) if !@idAttribute.nil? && element.respond_to?(@idAttribute)),
      :path => prePath
    }

    @referenceStrings[element] = refs
    eachReferencedElement(element, containmentReferences(element)) do |r,te,index|
      next if te.nil?
      # build path-based reference string
      path = te.eContainingFeature.to_s
      unless index.nil?
        indexed = false
        if @configuration[:refStringPathFormat] == "name"
          unless te.nil? || !te.respond_to?(:name) || te&.name.nil?
            path = "#{path}.#{te.name}"
            indexed = true
          end
        end
        # indexed references are a fallback when name is not available, also default.
        path = "#{path}.#{index.to_s}" unless indexed
      end
      # build name-based reference string
      name = te.eContainingFeature.to_s
      unless te.nil? || !te.respond_to?(:name) || te&.name.nil?
        name = te.name
      end
      buildReferenceStrings(te, "#{preName}/#{name}", "#{prePath}/@#{path}")
    end
  end

  def getReferenceString(element)
    if @configuration.key?(:refStringFormat)
      @configuration[:refStringFormat].each{|f|
        next if @referenceStrings[element].nil?
        return @referenceStrings[element][f.to_sym] unless @referenceStrings[element][f.to_sym].nil?
      }
      raise "No reference string for #{(element.respond_to?(:name) ? element.name : "<no name>")} (#{element}) in the configured formats."
    else
      return @referenceStrings[element][:name]
      return @referenceStrings[element][:id]
      return @referenceStrings[element][:path]
    end
  end

  def addBuiltinReferenceStrings
    def ref(str)
      pre = "ecore:EDataType http://www.eclipse.org/emf/2002/Ecore"
      hash = { :name => pre+str, :id => nil, :path => nil }
    end
    @referenceStrings[RGen::ECore::EString] = ref("#//EString")
    @referenceStrings[RGen::ECore::EInt] = ref("#//EInt")
    @referenceStrings[RGen::ECore::ELong] = ref("#//ELong")
    @referenceStrings[RGen::ECore::EFloat] = ref("#//EFloat")
    @referenceStrings[RGen::ECore::EDouble] = ref("#//EDouble")
    @referenceStrings[RGen::ECore::EBoolean] = ref("#//EBoolean")
    @referenceStrings[RGen::ECore::EDate] = ref("#//EDate")
    @referenceStrings[RGen::ECore::EJavaObject] = ref("#//EJavaObject")
    @referenceStrings[RGen::ECore::EJavaClass] = ref("#//EJavaClass")
  end

end

end

end
