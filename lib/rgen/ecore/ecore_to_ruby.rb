require 'rgen/ecore/ecore'

module RGen
  
module ECore

class ECoreToRuby
  
  def initialize
    @modules = {}
    @classifiers = {}
  end

  def create_module(epackage)
    return @modules[epackage] if @modules[epackage]
    
    m = Module.new do
      extend RGen::MetamodelBuilder::ModuleExtension
    end
    @modules[epackage] = m

    epackage.eSubpackages.each{|p| create_module(p)}
    epackage.eClassifiers.each do |c| 
      if c.is_a?(RGen::ECore::EClass)
        create_class(c)
      elsif c.is_a?(RGen::ECore::EEnum)
        create_enum(c)
      end
    end

    create_module(epackage.eSuperPackage).const_set(epackage.name, m) if epackage.eSuperPackage
    m
  end

  def create_class(eclass)
    return @classifiers[eclass] if @classifiers[eclass]

    c = Class.new(super_class(eclass)) do
      abstract if eclass.abstract
    end
    @classifiers[eclass] = c

    create_module(eclass.ePackage).const_set(eclass.name, c)
    c
  end

  def create_enum(eenum)
    return @classifiers[eenum] if @classifiers[eenum]

    e = RGen::MetamodelBuilder::DataTypes::Enum.new(eenum.eLiterals.collect{|l| l.name.to_sym})
    @classifiers[eenum] = e

    create_module(eenum.ePackage).const_set(eenum.name, e)
    e
  end

  class FeatureWrapper
    def initialize(efeature, classifiers)
      @efeature = efeature
      @classifiers = classifiers
    end
    def value(prop)
      @efeature.send(prop)
    end
    def many
      @efeature.many
    end
    def opposite
      @efeature.eOpposite
    end
    def impl_type
      etype = @efeature.eType
      if etype.is_a?(RGen::ECore::EClass) || etype.is_a?(RGen::ECore::EEnum)
        @classifiers[etype]
      elsif etype.name == "EString"
        String
      elsif etype.name == "EInt"
        Integer
      elsif etype.name == "EFloat"
        Float
      elsif etype.name == "EBoolean"
        RGen::MetamodelBuilder::DataTypes::Boolean
      end
    end
  end

  def add_features(eclass)
    c = @classifiers[eclass]
    eclass.eStructuralFeatures.each do |f|
      w1 = FeatureWrapper.new(f, @classifiers) 
      w2 = FeatureWrapper.new(f.eOpposite, @classifiers) if f.is_a?(RGen::ECore::EReference) && f.eOpposite
      c.module_eval do
        if w1.many
          _build_many_methods(w1, w2)
        else
          _build_one_methods(w1, w2)
        end
      end
    end
  end

  def super_class(eclass)
    super_types = eclass.eSuperTypes
    case super_types.size
    when 0
      RGen::MetamodelBuilder::MMBase
    when 1
      create_class(super_types.first)
    else
      RGen::MetamodelBuilder::MMMultiple(*super_types.collect{|t| create_class(t)})
    end
  end

end

end

end

