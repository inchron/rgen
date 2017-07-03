require 'rgen/ecore/ecore'
require 'json'

module RGen

module ECore

# ECoreToJson can turn ECore models into their JSON metamodel representations
class ECoreToJson

def initialize

end
  
def root_elements_to_json_string(root_elements)
  JSON.pretty_generate(root_elements.map do |el|
    if el.is_a?(RGen::ECore::EPackage)
      epackage(el)
    elsif el.is_a?(RGen::ECore::EClass)
      eclass(el)
    else
      raise "Not implemented for #{el}"
    end
  end)
end

def epackage_to_json(package)
  epackage(package)
end

def datatypes
  [RGen::ECore::EString, RGen::ECore::EInt, RGen::ECore::ELong, RGen::ECore::EBoolean, RGen::ECore::EFloat,
   RGen::ECore::ERubyObject, RGen::ECore::EJavaObject, RGen::ECore::ERubyClass, RGen::ECore::EJavaClass]
      .map {|dt| edatatype(dt)}
end

def epackage_to_json_pretty_string(package)
  JSON.pretty_generate([epackage_to_json(package)] + datatypes)
end

def epackage_to_json_string(package)
  JSON.generate([epackage_to_json(package)] + datatypes)
end
  
def emodelelement(me)
  {
    :eAnnotations => me.eAnnotations.map { |e| eannotation(e) }
  }
end


def enamedelement(ne)
  merge(emodelelement(ne), {:name => ne.name})
end

def epackage(package)
  merge(enamedelement(package), {
    :_class => 'RGen.ECore.EPackage',
    :eClassifiers => package.eClassifiers.map do |classifier|
      if classifier.is_a?(RGen::ECore::EClass)
        eclass(classifier)
      elsif classifier.is_a?(RGen::ECore::EEnum)
        eenum(classifier)
      else
        edatatype(classifier)
      end
    end,
    :eSubpackages => package.eSubpackages.map { |sp| epackage(sp) },
    :nsURI => package.nsURI,
    :nsPrefix => package.nsPrefix
  })
end
  
def eclassifier(classifier)
  enamedelement(classifier).merge({
    # omit :instanceClassName => classifier.instanceClassName
  })
end
  
def eclass(_class)
  merge(eclassifier(_class), {
    :_class => 'RGen.ECore.EClass',
    :abstract => _class.abstract,
    :interface => _class.interface,
    :eStructuralFeatures => _class.eStructuralFeatures.map do |sf|
      if sf.is_a?(RGen::ECore::EReference)
        ereference(sf)
      else
        eattribute(sf)
      end
    end,
    :eSuperTypes => _class.eSuperTypes.map { |st| {:_ref => ref_id(st)} }
  })
end
  
def edatatype(_datatype)
  merge(eclassifier(_datatype), {
    :_class => 'RGen.ECore.EDataType',
    :serializable => _datatype.serializable,
    :instanceClassName => _datatype.instanceClassName
  })
end

def eenum(enum)
  merge(edatatype(enum), {
    :_class => 'RGen.ECore.EEnum',
    :eLiterals => enum.eLiterals.map do |l|
      merge({}, {
        :_class => 'RGen.ECore.EEnumLiteral',
        :value => l.value,
        :literal => l.literal
      })
    end      
  })
end

def eannotation(e)
  merge(emodelelement(e), {
    :source => e.source,
    :details => e.details.map do |d|
      merge({}, {
          :_class => 'RGen.ECore.EStringToStringMapEntry',
          :key => d.key,
          :value => d.value
      })
    end
  })
end

def etypedelement(te)
  merge(enamedelement(te), {
    :ordered => te.ordered,
    :unique => te.unique,
    :lowerBound => te.lowerBound,
    :upperBound => te.upperBound,
    :many => te.many,
    :required => te.required,
    :eType => {:_ref => te.eType ? ref_id(te.eType) : nil}
  })
end

def estructuralfeature(sf)
  merge(etypedelement(sf), {
    :changeable => sf.changeable,
    :volatile => sf.volatile,
    :transient => sf.transient,
    :defaultValueLiteral => sf.defaultValueLiteral,
    :unsettable => sf.unsettable,
    :derived => sf.derived,
  })
end
  
def eattribute(attr)
  merge(estructuralfeature(attr), {
    :_class => 'RGen.ECore.EAttribute',
    :iD => attr.iD
  })
end
  
def ereference(ref)
  merge(estructuralfeature(ref), {
    :_class => 'RGen.ECore.EReference',
    :containment => ref.containment,
    :resolveProxies => ref.resolveProxies,
    :eOpposite => ref.eOpposite ? {:_ref => "#{ref_id(ref.eOpposite.eContainer)}.#{ref.eOpposite.name}"} : nil
  })
end
  
def ref_id(obj)
  res = ref_parts(obj)
  res.join('.')
end
  
def ref_parts(obj)
  return [obj.name] unless obj&.eContainer
  ref_parts(obj.eContainer) << obj.name 
end
  
def merge(hash, values)
  values.each { |k, v| hash[k] = v unless v.nil? }
  hash
end
  
end
  
end
  
end