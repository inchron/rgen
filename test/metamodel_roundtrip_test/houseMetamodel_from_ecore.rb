require 'rgen/metamodel_builder'

module HouseMetamodel
   extend RGen::MetamodelBuilder::ModuleExtension
   include RGen::MetamodelBuilder::DataTypes

   EcoreNsURI = "http://example.com/house"
   EcoreNsPrefix = "house"
   SexEnum = Enum.new(:name => 'SexEnum', :literals =>[ :male, :female ])


   class House < RGen::MetamodelBuilder::MMBase
      annotation :source => "bla", :details => {"abc" => "A \"text\" with some 'quotes'."}
      has_attr 'address', String, :changeable => false, :iD => false 
   end

   class MeetingPlace < RGen::MetamodelBuilder::MMBase
   end

   class Person < RGen::MetamodelBuilder::MMBase
      has_attr 'sex', HouseMetamodel::SexEnum, :iD => false 
      has_attr 'id', Long, :iD => false 
      has_attr 'height', Double, :iD => false 
      has_attr 'birthday', Date, :iD => false 
      has_many_attr 'nicknames', String, :iD => false 
   end


   module Rooms
      extend RGen::MetamodelBuilder::ModuleExtension
      include RGen::MetamodelBuilder::DataTypes

      EcoreNsURI = "http://example.com/house/rooms"
      EcoreNsPrefix = "rooms"


      class Room < RGen::MetamodelBuilder::MMBase
      end

      class Bathroom < Room
      end

      class Kitchen < RGen::MetamodelBuilder::MMMultiple(Room, HouseMetamodel::MeetingPlace)
      end

   end
end

HouseMetamodel::House.has_one 'bathroom', HouseMetamodel::Rooms::Bathroom, :lowerBound => 1 
HouseMetamodel::House.one_to_one 'kitchen', HouseMetamodel::Rooms::Kitchen, 'house', :lowerBound => 1 
HouseMetamodel::House.contains_many 'room', HouseMetamodel::Rooms::Room, 'house' 
HouseMetamodel::Person.has_many 'house', HouseMetamodel::House 
