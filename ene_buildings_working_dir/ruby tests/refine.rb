module RefineTest

  refine Sketchup::AttributeDictionary do
  
    def to_hash

      h = {}
      each_pair { |k, v| h[k] = v }

      h

    end
  
  end
  
  puts Sketchup::AttributeDictionary.new.to_hash
  
  dict_name = "test"
  entity = Sketchup.active_model.selection.first
  ad = entity.attribute_dictionary dict_name
  
  puts ad.to_hash

end