require 'set'

module RGen

module Serializer

class XMLSerializer

  INDENT_SPACE = 2

  def initialize(file)
    @indent = 0
    @lastStartTag = nil
    @textContent = false
    @file = file
    @config = {}
  end

  def serialize(rootElement, configuration={})
    raise "Abstract class, overwrite method in subclass!"
  end

  # Expects an array of 2d arrays
  def prolog(opts=[])
    output "<?xml version=\"1.0\""
    for attrs in opts
      raise ArgumentError.new(
        "Wrong number of prolog attribute elements, expected tuple but got length of #{attrs.size}"
      ) unless attrs.size == 2
      output  " #{attrs[0]}=\"#{attrs[1]}\""
    end
    output " ?>\n"
  end

  def gatherNamespaces(element, namespaces = Set.new)
    return unless element
    ns = element.class.ecore.ePackage.nsPrefix
    uri = element.class.ecore.ePackage.nsURI
    namespaces << ["xmlns:#{ns}", uri] unless uri.nil?
    eachReferencedElement(element, containmentReferences(element)) do |r,te|
      next unless te
      namespaces += gatherNamespaces(te, namespaces)
    end
    namespaces
  end

  def startTag(tag, attributes={})
    @textContent = false
    handleLastStartTag(false, true)
    if attributes.is_a?(Hash)
      attrString = attributes.keys.collect{|k| "#{k}=\"#{attributes[k]}\""}.join(" ")
    else
      attrString = attributes.collect{|pair| "#{pair[0]}=\"#{pair[1]}\""}.join(" ")
    end
    @lastStartTag = " "*@indent*INDENT_SPACE + "<#{tag} "+attrString
    @indent += 1
  end

  def endTag(tag)
    @indent -= 1
    unless handleLastStartTag(true, true)
      output " "*@indent*INDENT_SPACE unless @textContent
      output "</#{tag}>\n"
    end
    @textContent = false
  end

  def writeText(text)
    handleLastStartTag(false, false)
    output "#{text}"
    @textContent = true
  end

  protected

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

  def eachReferencedElement(element, refs, &block)
    refs.each do |r|
      targetElements = element.getGeneric(r.name) unless r.derived
      unless targetElements.is_a?(Array)
        yield(r,targetElements,nil)
      else
        targetElements.each_with_index do |te, index|
          yield(r,te,index)
        end
      end
    end
  end

  def containmentReferences(element)
    @containmentReferences ||= {}
    @containmentReferences[element.class] ||= eAllReferences(element).select{|r| r.containment}
  end

  private

  def handleLastStartTag(close, newline)
    return false unless @lastStartTag
    output @lastStartTag
    output close ? "/>" : ">"
    output "\n" if newline
    @lastStartTag = nil
    true
  end

  def output(text)
    @file.write(text)
  end

end

end

end
