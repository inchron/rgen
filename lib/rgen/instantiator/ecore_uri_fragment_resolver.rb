module RGen

module Instantiator

class EcoreUriFragmentResolver
  class << self
    def get_object_relative_to(object, uri_fragment)
      return nil if uri_fragment.blank? || uri_fragment[0] != "/"

      get_object_for_uri_fragment_path(object, uri_fragment)
    end

    private

    FeatureNameAndId = Struct.new(:feature_name, :id)

    def get_object_for_uri_fragment_path(start_object, uri_fragment_path)
      path_segments = uri_fragment_path.split("/").compact.reject{|s| s.empty?}
      return nil if path_segments.empty?
      first_feature_name = extract_feature_and_id_from_uri_fragment_segment(path_segments.first).feature_name
      current_object = search_recursive_first_object_with_feature(start_object, first_feature_name)

      path_segments.each{ |path_segment|
        return nil if current_object.nil?
        segment = extract_feature_and_id_from_uri_fragment_segment(path_segment)
        feature_name = segment.feature_name
        return nil if feature_name.blank?
        return nil unless current_object.class.ecore.eAllStructuralFeatures.any?{|f| f.name == feature_name}
        feature = current_object.send(feature_name)
        return nil if feature.nil?
        id = segment.id
        if id.blank?
          current_object = feature
        else
          current_object = feature.find{|o|
            o.respond_to?(:name) && o.name == id
          }
          if current_object.nil? && /^\d+$/.match?(id)
            current_object = feature[id.to_i]
          end
        end
      }
      current_object
    end

    def extract_feature_and_id_from_uri_fragment_segment(segment)
      return nil if segment.empty?
      segment = segment[1..-1] if segment[0] == '@'
      id = nil;
      dotIndex = segment.index('.');
      unless dotIndex.nil?
        id = segment[(dotIndex + 1)..-1]
        id = URI.decode_www_form_component(id) unless id.nil?
        segment.slice!(dotIndex..-1)
      end
      return FeatureNameAndId.new(segment, id)
    end

    def search_recursive_first_object_with_feature(start_object, feature_name)
      current_object = start_object
      while not current_object.nil?
        efeature = current_object.class.ecore.eAllStructuralFeatures.find{ |f|
          f.name == feature_name
        }
        if efeature.nil?
          current_object = current_object.eContainer
        else
          break
        end
      end
      if current_object.nil?
        puts "WARNING: No object found with feature '#{feature_name}' relative to object '#{start_object.name}'"
      end
      return current_object
    end
  end
end

end

end
