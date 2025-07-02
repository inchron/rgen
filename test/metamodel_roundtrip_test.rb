$:.unshift File.join(File.dirname(__FILE__),"..","lib")

require 'minitest/autorun'
require 'rgen/array_extensions'
require 'rgen/util/model_comparator'
require 'mmgen/metamodel_generator'
require 'rgen/instantiator/ecore_xml_instantiator'
require 'rgen/instantiator/ecore_model_xml_instantiator'
require 'rgen/serializer/xmi20_serializer'

class MetamodelRoundtripTest < Minitest::Test

  TEST_DIR = File.dirname(__FILE__)+"/metamodel_roundtrip_test"

  include MMGen::MetamodelGenerator
  include RGen::Util::ModelComparator

  module Regenerated
    Inside = binding
  end

  module TestGenerator # module wrapper for load in test_generator
  end

  module TestEcoreSerializer # module wrapper for load in test_ecore_serializer
  end

  module TestGenerateFromEcore # module wrapper for load in test_ecore_serializer
  end

  module TestSerializeModel
  end

  include TestGenerator
  include TestEcoreSerializer
  include TestGenerateFromEcore
  include TestSerializeModel

  def test_generator
    load(TEST_DIR+"/TestModel.rb", TestGenerator) # load into module TestGenerator
    outfile = TEST_DIR+"/TestModel_Regenerated.rb"
    generateMetamodel(HouseMetamodel.ecore, outfile)

    File.open(outfile) do |f|
      eval(f.read, Regenerated::Inside)
    end

    assert modelEqual?(HouseMetamodel.ecore, Regenerated::HouseMetamodel.ecore, ["instanceClassName"])
  end

  module UMLRegenerated
    Inside = binding
  end

  def test_generate_from_ecore
    infile1 = TEST_DIR+"/houseMetamodel.ecore"
    infile2 = TEST_DIR+"/propertyMetamodel.ecore"
    outfile1 = TEST_DIR+"/houseMetamodel_from_ecore.rb"
    outfile2 = TEST_DIR+"/propertyMetamodel_from_ecore.rb"

    env = RGen::Environment.new
    name = "HouseMetamodel"
    File.open(infile1) {|f| ECoreXMLInstantiator.new(env).instantiate(name, f)}
    generateMetamodel(env.rootPackage(name), outfile1)
    # check if it loads without error
    load(outfile1, TestGenerateFromEcore)

    name = "PropertyMetamodel"
    File.open(infile2) {|f| ECoreXMLInstantiator.new(env).instantiate(name, f)}
    generateMetamodel(env.rootPackage(name), outfile2)
    # check if it loads without error
    load(outfile2, TestGenerateFromEcore)

    assert_equal(
      HouseMetamodel::Rooms::Kitchen.superclass.multiple_superclasses.size,
      2
    )

    propertyClass = PropertyMetamodel::Property
    # Ensure we have a HouseMetamodel::House inside PropertyMetamodel
    assert_equal(
      propertyClass.ecore.eReferences.first.eType.name,
      "House"
    )

    assert_equal(
      propertyClass.ecore.eReferences.find{|f| f.name == "ObjectTest" }.eType.name,
      "EObject"
    )

    File.open(outfile1) do |f|
      eval(f.read, UMLRegenerated::Inside, "test_eval", 0)
    end
    File.open(outfile2) do |f|
      eval(f.read, UMLRegenerated::Inside, "test_eval", 0)
    end
  end

  def test_serialize_instance
    infile1 = TEST_DIR+"/houseMetamodel_from_ecore.rb"
    infile2 = TEST_DIR+"/propertyMetamodel_from_ecore.rb"
    infile3 = TEST_DIR+"/propertyInstance.xml"
    outfile = TEST_DIR+"/propertyInstance_regenerated.xml"
    load(infile1, TestSerializeModel)
    load(infile2, TestSerializeModel)

    env = RGen::Environment.new
    instanceFile = File.open(infile3)
    doc = Nokogiri.XML(instanceFile)
    instantiator = RGen::Instantiator::EcoreModelXmlInstantiator.new(
      env, [PropertyMetamodel, HouseMetamodel]
    )
    instantiator.instantiate(doc.to_s)
    property = env.find(class: PropertyMetamodel::Property).first

    File.open(outfile,"w") do |f|
      serializer = RGen::Serializer::XMI20Serializer.new(f)
      serializer.serialize(property, {
            prolog: [["encoding", "UTF-8"], ["standalone", "no"]]
      })
    end

    outdoc = Nokogiri.XML(File.open(outfile))
    assert_equal(doc.to_s, outdoc.to_s) # to_s should have normalized outputr

  end

  def test_ecore_serializer
    load(TEST_DIR+"/TestModel.rb", TestEcoreSerializer)
    File.open(TEST_DIR+"/houseMetamodel_Regenerated.ecore","w") do |f|
	  	ser = RGen::Serializer::XMI20Serializer.new(f)
	  	ser.serialize(HouseMetamodel.ecore)
	 	end
  end

  BuiltinTypesTestEcore = TEST_DIR+"/using_builtin_types.ecore"

  def test_ecore_serializer_builtin_types
    mm = RGen::ECore::EPackage.new(:name => "P1", :eClassifiers => [
      RGen::ECore::EClass.new(:name => "C1", :eStructuralFeatures => [
        RGen::ECore::EAttribute.new(:name => "a1", :eType => RGen::ECore::EString),
        RGen::ECore::EAttribute.new(:name => "a2", :eType => RGen::ECore::EInt),
        RGen::ECore::EAttribute.new(:name => "a3", :eType => RGen::ECore::ELong),
        RGen::ECore::EAttribute.new(:name => "a4", :eType => RGen::ECore::EFloat),
        RGen::ECore::EAttribute.new(:name => "a5", :eType => RGen::ECore::EDouble),
        RGen::ECore::EAttribute.new(:name => "a6", :eType => RGen::ECore::EBoolean),
        RGen::ECore::EAttribute.new(:name => "a7", :eType => RGen::ECore::EDate),
      ])
    ])
    outfile = TEST_DIR+"/using_builtin_types_serialized.ecore"
    File.open(outfile, "w") do |f|
      ser = RGen::Serializer::XMI20Serializer.new(f)
      ser.serialize(mm)
    end
    assert_equal(File.read(BuiltinTypesTestEcore), File.read(outfile))
  end

  def test_ecore_instantiator_builtin_types
    env = RGen::Environment.new
    File.open(BuiltinTypesTestEcore) { |f|
      ECoreXMLInstantiator.new(env).instantiate(BuiltinTypesTestEcore, f)
    }
    a1 = env.find(:class => RGen::ECore::EAttribute, :name => "a1").first
    assert_equal(RGen::ECore::EString, a1.eType)
    a2 = env.find(:class => RGen::ECore::EAttribute, :name => "a2").first
    assert_equal(RGen::ECore::EInt, a2.eType)
    a3 = env.find(:class => RGen::ECore::EAttribute, :name => "a3").first
    assert_equal(RGen::ECore::ELong, a3.eType)
    a4 = env.find(:class => RGen::ECore::EAttribute, :name => "a4").first
    assert_equal(RGen::ECore::EFloat, a4.eType)
    a5 = env.find(:class => RGen::ECore::EAttribute, :name => "a5").first
    assert_equal(RGen::ECore::EDouble, a5.eType)
    a6 = env.find(:class => RGen::ECore::EAttribute, :name => "a6").first
    assert_equal(RGen::ECore::EBoolean, a6.eType)
    a7 = env.find(:class => RGen::ECore::EAttribute, :name => "a7").first
    assert_equal(RGen::ECore::EDate, a7.eType)
  end

end
