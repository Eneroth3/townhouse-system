# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

# Internal: UI for creating and editing Templates.
#
# A template can be loaded as a component and edited within any model.
# The template info (what is saved as info.json in the template file) is
# temporarily stored as attributes to the component instance.
#
# A new template can also be created with an empty component definition and no
# attributes.
#
# The component can be modified as usual in Sketchup and the attributes from
# a dialog window.
#
# The component definition along with the attributes can be saved back to a 
# template file when done editing.
module TemplateEditor

  # Attribute dictionary to store template info to while editing template.
  # When template is saved to file this data is written to the JSON.
  # file in it.
  ATTR_DICT_EDITING = "#{ID}_editing"

  # Dialogs.
  @@dlg      ||= nil
  @@dlg_part ||= nil
  @@dlg_open ||= nil

  # Component instance which attributes are being edited in template info.
  # Either a selected component instance or one opened for editing.
  @@component_inst ||= nil

  # Group/component which attributes are being edited in part info dialog.
  @@part ||= nil
  
  @@update_previes = true unless defined? @@update_previes

  # Module variable accessors
  
  # Internal: Whether preview images should be automatically updates or not on
  # template save
  def self.update_previes; @@update_previes; end
  def self.update_previes=(v); @@update_previes = v; end
  
  # Module methods
  
  # Returns component instance representing template currently being edited.
  # Either this is selected or user is editing within it.
  # nil when no template is currently being edited.
  def self.active_template_component

    model = Sketchup.active_model
    component_inst = inside_template_component
    selection = model.selection
    selected = selection.first
    if(
      !component_inst &&
      selection.size == 1 &&
      selected &&
      selected.is_a?(Sketchup::ComponentInstance) &&
      Template.component_is_template?(selected)
    )
      component_inst = selected
    end

    component_inst

  end

  # Save all template attributes as attributes to component instance,
  # except the component reference.
  # Called from .open and observer for placing component.
  #
  # Returns nothing.
  def self.attach_template_data_to_component(template, instance)

    model = instance.model
    model.start_operation "Attach template data", true, false, true

    template.instance_variables.each do |key|
      value = template.instance_variable_get(key)
      key = key.to_s  # Make string of symbol
      key[0] = ""     # Remove @ sign from key
      instance.set_attribute ATTR_DICT_EDITING, key, value
    end

    model.commit_operation

    nil

  end

  # Open template info dialog to set ID, name etc.
  #
  # Returns nothing.
  def self.info_dialog

    if @@dlg
      @@dlg.bring_to_front
    else
    
      # Make sure installed templates are loaded so preview image for a taking
      # ID can be shown.
      Template.require_all

      # Open web dialog and load data from selected entity.
      @@dlg = UI::WebDialog.new("Template Info", false, "#{ID}_template_editor", 430, 450, 100, 100, true)
      @@dlg.min_width = 430
      @@dlg.min_height = 300
      @@dlg.navigation_buttons_enabled = false
      @@dlg.set_file(File.join(PLUGIN_DIR, "dialogs", "template_editor.html"))
      if Sketchup.platform == :platform_win
        @@dlg.show { load_info }
      else
        @@dlg.show_modal { load_info }
      end

      # Closing dialog.
      @@dlg.set_on_close do
        #Save data.
        save_info

        @@dlg = nil
      end

      # Close button or Esc.
      @@dlg.add_action_callback("close") do
        @@dlg.close
      end

      # Open help.
      @@dlg.add_action_callback("help") do
        show_docs
      end

      # Make ID suggestion based on template and author name.
      @@dlg.add_action_callback("make_id_suggestion") do
        name = @@dlg.get_element_value "name"
        modeler = @@dlg.get_element_value "modeler"
        id = EneBuildings.make_id_suggestion name, modeler
        next unless id
        js = "document.getElementById('id').value=#{id.inspect};"
        js << "load_preview();"
        @@dlg.execute_script js
      end

      # Update preview image based on ID when ID changes.
      # If a Template is saved by that ID the preview image of it is shown,
      # otherwise a placeholder image.
      @@dlg.add_action_callback("load_preview") do
        id = @@dlg.get_element_value "id"
        img_path = File.join Template::PREVIEW_DIR, "#{id}_100.png"
        img_path = Template::PREVIEW_PLACEHOLDER_100 unless File.exist?(img_path)
        img_path += "?no_cache=#{Time.now.to_i}"
        js = "set_image_path(#{img_path.inspect});"
        @@dlg.execute_script js
      end

    end

    nil

  end

  def self.info_opened?

    @@dlg && @@dlg.visible?

  end

  def self.info_toggle

    info_opened? ? @@dlg.close : info_dialog

  end

  # Template defining component user is currently inside or nil.
  #
  # Returns ComponentInstance or nil.
  def self.inside_template_component

    model = Sketchup.active_model
    active_path = model.active_path || []

    active_path.find do
      |c| Template.component_is_template? c
    end

   end

  # Drawing context being the root of a template component?
  def self.in_template_root?

    model = Sketchup.active_model
    active_path = model.active_path || []
    return false if active_path.empty?
    return false unless Template.component_is_template? active_path.last

    true

  end

  # Sets @@component_inst to template component instance currently selected or
  # opened and load attributes to template info dialog.
  #
  # Called when opening dialog and from observer when election or drawing
  # context changes.
  #
  # Returns nothing.
  def self.load_info

    @@component_inst = active_template_component

    if !@@component_inst
      #No active template to edit.
      title = "No active template."
      msg = "Please select a single template component."
      js = "warn(true, '#{title}', '#{msg}');"
      @@dlg.execute_script js

    else

      info = EneBuildings.attr_dict_to_hash(@@component_inst, ATTR_DICT_EDITING)
      img_path = File.join Template::PREVIEW_DIR, "#{info["id"]}_100.png"
      img_path = Template::PREVIEW_PLACEHOLDER_100 unless File.exist?(img_path)
      img_path += "?no_cache=#{Time.now.to_i}"
      info["alignment"] = [nil, nil] unless info["alignment"]
      suggest_id = !info["name"] || !info["modeler"]

      js = "warn(false);"
      js << "document.getElementById('name').value=#{info["name"].to_s.inspect};"
      js << "document.getElementById('modeler').value=#{info["modeler"].to_s.inspect};"
      js << "document.getElementById('id').value=#{info["id"].to_s.inspect};"
      js << "suggest_id(#{suggest_id});"
      js << "document.getElementById('architect').value=#{info["architect"].to_s.inspect};"
      js << "document.getElementById('country').value=#{info["country"].to_s.inspect};"
      js << "document.getElementById('year').value=#{info["year"].to_s.inspect};"
      js << "document.getElementById('stories').value=#{info["stories"].to_s.inspect};"
      js << "document.getElementById('source').value=#{info["source"].to_s.inspect};"
      js << "document.getElementById('source_url').value=#{info["source_url"].to_s.inspect};"
      js << "document.getElementById('description').value=#{info["description"].to_s.inspect};"
      js << "document.getElementById('alignment_front').value=#{info["alignment"][0].to_s.inspect};"
      js << "document.getElementById('alignment_back').value=#{info["alignment"][1].to_s.inspect};"
      js << "document.getElementById('depth').value=#{info["depth"].to_s.inspect};"
      js << "set_image_path(#{img_path.inspect});"
      @@dlg.execute_script js

    end

    nil

  end

  # Sets @@part to what is currently selected and load attributes to part info
  # dialog.
  #
  # Called when opening dialog and from observer when selection changes.
  #
  # Returns nothing.
  def self.load_part_data

    model = Sketchup.active_model
    @@part = model.selection.first
    unless [Sketchup::Group, Sketchup::ComponentInstance].include?(@@part.class)
      @@part = nil
    end
    @@part = nil unless inside_template_component
    @@part = nil unless model.selection.length == 1

    if !inside_template_component
      # Active drawing context is not within a template defining component.

      title = "Not available outside template component."
      msg = "Please enter a template component."
      js = "warn(true, '#{title}', '#{msg}');"
      @@dlg_part.execute_script js

    elsif !@@part
      # Selection cannot be edited.

      title = "Not available for this selection."
      msg = "Please select a single group or component."
      js = "warn(true, '#{title}', '#{msg}');"
      @@dlg_part.execute_script js

    else
      # Selection can be edited, load its current attributes to form.

      # Get attributes. Empty hash when part settings have not yet been set.
      data = EneBuildings.attr_dict_to_hash(@@part, Template::ATTR_DICT_PART)

      # Get variables to use in form.
      # Form differs slightly from attributes to be more user intuitive.
      # TODO: CODE IMPROVEMENT: list default values both here and in save_attributes?
      percentage = 0
      spread_fix_number = false
      spread_distance = ""
      spread_int = 1
      position_method =
        if data["align"]
          if data["align"].is_a? String
            data["align"]
          else
            percentage = data["align"]
            "percentage"
          end
        elsif data["spread"]
          spread_fix_number = data["spread"].is_a? Fixnum
          if spread_fix_number
            spread_int = data["spread"]
          else
            spread_distance = data["spread"]
          end
          "spread"
        elsif data["gable"]
          "gable"
        elsif data["corner"]
          "corner"
        else
          ""
        end
      name                    = data["name"]                    || ""
      margin                  = data["margin"]                  || 0.to_l
      margin_right            = data["margin_right"]            || ""
      rounding                = data["rounding"]                || ""
      override_cut_planes     = data["override_cut_planes"]     || false
      replace_nested_mateials = data["replace_nested_mateials"] || false
      gable_margin            = data["gable_margin"]            || 0.to_l
      corner_margin           = data["corner_margin"]           || 0.to_l
      solid                   = data["solid"]                   || ""
      solid_index             = data["solid_index"]             || 0

      # Add data to dialog.
      js = "warn(false);"
      js << "document.getElementById('name').value=#{name.to_s.inspect};"
      js << "toggle_positioning(#{position_method.inspect});"
      js << "document.getElementById('margin').value=#{margin.to_s.inspect};"
      js << "document.getElementById('margin_right').value=#{margin_right.to_s.inspect};"
      js << "spread_fix_number(#{spread_fix_number});"
      js << "document.getElementById('spread_distance').value=#{spread_distance.to_s.inspect};"
      js << "document.getElementById('spread_int').value=#{spread_int};"
      js << "document.getElementById('rounding').value=#{rounding.inspect};"
      js << "document.getElementById('align_percentage').value=#{percentage};"
      js << "override_cut_planes(#{override_cut_planes});"
      js << "document.getElementById('gable_margin').value=#{gable_margin.to_s.inspect};"
      js << "document.getElementById('corner_margin').value=#{corner_margin.to_s.inspect};"
      js << "replace_nested_mateials(#{replace_nested_mateials});"
      js << "is_group(#{@@part.is_a? Sketchup::Group});"
      js << "document.getElementById('solid').value=#{solid.inspect};"
      js << "toggle_solid();"
      js << "document.getElementById('solid_index').value=#{solid_index};"
      js << "var in_template_root = #{in_template_root?};"
      js << "toggle_sections();"
      @@dlg_part.execute_script js

    end

    nil

  end

  # Create component instance to base new template on.
  #
  # Returns nothing.
  def self.new

    model = Sketchup.active_model
    ents = model.active_entities
    selection = model.selection
    view = model.active_view

    # Temporary set camera to preview angle for consistent component thumbnails.
    Template.set_preview_camera
    view.invalidate

    Observers.disable

    model.start_operation "Create Template Component", true

    # If selection is a group, base template on it.
    # Otherwise first group selection.
    group =
      if selection.length == 1 && selection.first.is_a?(Sketchup::Group)
        selection.first
      else
        ents.add_group selection.to_a
    end

    componen_inst = group.to_component
    definition = componen_inst.definition
    definition.name = Template::COMPONENT_NAME_PREFIX + "Untitled"

    model.commit_operation

    # Reset camera
    Template.reset_camera

    selection.clear
    selection.add componen_inst
    onSelectionChange

    Observers.enable

    nil

  end

  # Determines whether "New" should be available in menus depending on current
  # selection.
  #
  # Disabled when
  #  selection is empty,
  #  inside template component,
  #  selection contains template defining component and
  #  when selection contains building group.
  #
  # Returns boolean.
  def self.new_available?

    model = Sketchup.active_model
    selection = model.selection

    return if selection.empty?
    return if active_template_component
    return if selection.any? { |e| Building.group_is_building? e }

    true

  end

  # Called when drawing context is changed.
  # Use name matching those in observer and tool interface instead of following
  # best practice.
  def self.onActivePathChanged

    # Save data for previously selected template and load data for the new one
    # if template has changed.
    if info_opened? && active_template_component != @@component_inst
      save_info
      load_info
    end

    # Save data for previously selected part and load data for the new one.
    if part_info_opened?
      save_part_data
      load_part_data
    end

  end

  # Called when user enters component defining template.
  def self.onComponentEnter

    return if Sketchup.read_default ID, "template_entering_no_warning", false

    dlg = UI::WebDialog.new("Entering Template Component", false, "#{ID}_template_entering", 450, 200, 300, 200, false)
    dlg.navigation_buttons_enabled = false
    dlg.set_file(File.join(PLUGIN_DIR, "dialogs", "template_entering.html"))
    if Sketchup.platform == :platform_win
      dlg.show
    else
      dlg.show_modal
    end

    # OK button.
    dlg.add_action_callback("close") do
      dlg.close
    end
    
    # Do not show me this again.
    dlg.add_action_callback("prevent") do |_, cb|
      Sketchup.write_default ID, "template_entering_no_warning", cb == "true"
    end
    
    # Help link.
    dlg.add_action_callback("help") do
      show_docs
    end
    
    nil

  end

  # Called when a component is placed from the component browser
  def self.onPlaceComponent(instance)

   definition = instance.definition
   template = Template.get_from_component_definition definition
   return unless template

   @@dlg_open.close if open_opened?

   Observers.disable
   attach_template_data_to_component template, instance
   selection = instance.model.selection
   selection.clear
   selection.add instance
   Observers.enable
   # Without 0 timer the active template cannot be found.
   UI.start_timer(0) { onSelectionChange }

  end

  # Called before model is saved.
  def self.onPreSaveModel

    save_info if info_opened?
    save_part_data if part_info_opened?

  end

  # Called from observer when selection changes.
  def self.onSelectionChange

    # Save data for previously selected template and load data for the new one
    # if template has changed.
    # Do not change if the active template component didn't change.
    if info_opened? && active_template_component != @@component_inst
      save_info
      load_info
    end

    # Save data for previously selected part and load data for the new one.
    if part_info_opened?
      save_part_data
      load_part_data
    end

  end

  # Called from observer when user undo or redo.
  def self.onUndoRedo

    load_info if info_opened?
    load_part_data if part_info_opened?

  end

  # Open an installed template for editing by placing its defining component
  # in model.
  #
  # Returns nothing.
  def self.open

    if open_opened?
      @@dlg_open.bring_to_front
    else

      title = "Open Template for Editing"
      @@dlg_open = Template.select_panel(title, nil, true) do |t|
        next unless t

        # Place component defining template.
        model = Sketchup.active_model
        model.place_component t.component_def

      end

    end

    nil

  end

  def self.open_opened?

    @@dlg_open && @@dlg_open.visible?

  end

  # Open part info dialog to set parts' positioning, material replacements etc.
  #
  # Returns nothing.
  def self.part_info_dialog

    if @@dlg_part
      @@dlg_part.bring_to_front
    else

      # Open web dialog and load data from selected entity.
      @@dlg_part = UI::WebDialog.new("Template Part Info", false, "#{ID}_template_editor_part", 430, 450, 110, 110, true)
      @@dlg_part.min_width = 430
      @@dlg_part.min_height = 300
      @@dlg_part.navigation_buttons_enabled = false
      @@dlg_part.set_file(File.join(PLUGIN_DIR, "dialogs", "template_editor_part.html"))
      if Sketchup.platform == :platform_win
        @@dlg_part.show { load_part_data }
      else
        @@dlg_part.show_modal { load_part_data }
      end

      # Closing dialog.
      @@dlg_part.set_on_close do
        #Save data.
        save_part_data

        @@dlg_part = nil
      end

      # Close button or Esc.
      @@dlg_part.add_action_callback("close") do
        @@dlg_part.close
      end

      # Open help.
      @@dlg_part.add_action_callback("help") do
        show_docs
      end

      # Turn selected component into group.
      @@dlg_part.add_action_callback("convert_to_group") do
        Observers.disable
        model = @@part.model
        model.start_operation "Convert to Group", true
        @@part = EneBuildings.component_to_group @@part
        model.selection.clear
        model.selection.add @@part
        load_part_data
        model.commit_operation
        Observers.enable
      end

    end

    nil

  end

  def self.part_info_opened?

    @@dlg_part && @@dlg_part.visible?

  end

  def self.part_info_toggle

    part_info_opened? ? @@dlg_part.close : part_info_dialog

  end

  # Save template currently being edited to its template archive file.
  # File name is based on ID set in template info.
  #
  # Returns nothing.
  def self.save
  
    # REVIEW: Should more of this stuff be moved to the Template class itself?
    # Low level stuff like creating json text file and saving component as
    # external skp file doesn't really belong in this user interface class.
    # "model.skp" and "info.json" should not be mentioned outside Template.
    # If this is changed, make sure Template does not show up in template
    # browser unless it's saved to a file too.

    unless active_template_component
      msg =
        "No active Template.\n"\
        "Select a template component and try again."
      UI.messagebox msg
      return
    end

    save_info if info_opened?
    info = EneBuildings.attr_dict_to_hash(active_template_component, ATTR_DICT_EDITING)

    unless info["id"]
      msg =
        "ID not set. A template cannot be saved without an ID.\n"\
        "Set an ID in the Template Info dialog and try again."
      UI.messagebox msg
      info_dialog
      return
    end
    
    unless Template.valdiate_component? active_template_component.definition
      msg =
        "Template does not have valid gables.\n\n"\
        "There must be exactly one face with negative X as normal and one with"\
        " positive X as normal directly in the template component for the"\
        " plugin to be able to draw a house.\n\n"\
        "Correct the gables and try again."
      UI.messagebox msg
      return
    end

    Template.require_all
    if Template.get_from_id info["id"]
      msg =
        "The template '#{Template.filename(info["id"])}' already exists.\nReplace it?\n\n"\
        "To save by another name, change the ID field in template info dialog."
      return if UI.messagebox(msg, MB_YESNO) == IDNO
    end
    
    Sketchup.status_text = "Saving template..."

    # If part data dialog is opened, save the values of it.
    save_part_data if part_info_opened?

    # ID should not be saved in the json file since it's defined in the name of
    # the whole template file.
    id = info.delete "id"

    # Empty temp directory.
    FileUtils.rm_rf Dir.glob(File.join(Template::EXTRACT_DIR, "*"))

    files = []

    # Save component definition.
    # The plugin is supported by SU 2015 and later. Save template as version
    # 2015 so it can be used in 2015 even if it's created in a newer version.
    version = Sketchup::Model::VERSION_2015
    path = File.join Template::EXTRACT_DIR, "model.skp"#, version#TODO: FUTURE SU VERSION: add version parameter when supported
    active_template_component.definition.save_as path
    files << path

    # Save data as json.
    path = File.join Template::EXTRACT_DIR, "info.json"
    json_string = JSON.generate info
    File.write path, json_string
    files << path

    # Compress files into template archive file.
    ###t.write_to_archive files# This requires Template object to be created and that currently requires the file to already exist.
    full_path = Template.full_path id
    EneBuildings.compress files, full_path

    # Empty temp directory.
    FileUtils.rm_rf Dir.glob(File.join(Template::EXTRACT_DIR, "*"))

    # Load/reload Template object for this template.
    t = Template.load_id id
    
    
    # Update template preview.
    # This draws a temporary Building using the Template and therefore must
    # be called after the rest of the template data is saved.
    if @@update_previes
      Sketchup.status_text = "Creating Preview..."
      t.update_preview
    end
    
    Sketchup.status_text = "Done saving."

    nil

  end

  # Save info for template currently being edited from template info dialog to
  # attributes in component instance representing it.
  #
  # Called when closing dialog, when saving template and from observer when
  # selection or drawing context changes.
  #
  # Returns nothing.
  def self.save_info

    return unless @@component_inst
    return if @@component_inst.deleted?
    
    # Get data already saved.
    old_data = EneBuildings.attr_dict_to_hash(@@component_inst, ATTR_DICT_EDITING)

    # Get settings from dialog.
    data = {}#TODO: CODE IMPROVEMENT:  use loop instead of repeating code.
    name = @@dlg.get_element_value "name"
    data["name"] = name unless name.empty?
    modeler = @@dlg.get_element_value "modeler"
    data["modeler"] = modeler unless modeler.empty?
    #@@suggest_id = @@dlg.get_element_value("suggest_id") == "true"
    id = @@dlg.get_element_value "id"
    unless id.empty?
      if /\W/.match id
        msg =
          "'ID must only contain letters A-Z and underscore (_).\n"\
          "Keeping old value."
        UI.messagebox msg
        id = old_data["id"]
      end
      data["id"] = id if id
    end
    architect = @@dlg.get_element_value "architect"
    data["architect"] = architect unless architect.empty?
    country = @@dlg.get_element_value "country"
    data["country"] = country unless country.empty?
    year = @@dlg.get_element_value("year")
    data["year"] = year.to_i unless year.empty?
    stories = @@dlg.get_element_value "stories"
    data["stories"] = stories.to_i unless stories.empty?
    source = @@dlg.get_element_value "source"
    data["source"] = source unless source.empty?
    source_url = @@dlg.get_element_value "source_url"
    data["source_url"] = source_url unless source_url.empty?
    description = @@dlg.get_element_value "description"
    data["description"] = description unless description.empty?
    alignment = [nil, nil]
    alignment_front = @@dlg.get_element_value "alignment_front"
    alignment_back = @@dlg.get_element_value "alignment_back"
    alignment[0] = alignment_front.to_i unless alignment_front.empty?
    alignment[1] = alignment_back.to_i unless alignment_back.empty?
    data["alignment"] = alignment
    depth = @@dlg.get_element_value "depth"
    if depth.start_with? "~"# Assume user didn't write value.
      data["depth"] = old_data["depth"]
    elsif !depth.empty?
      begin
        depth = depth.to_l
      rescue
        msg =
          "'#{depth}' could not be parsed as length.\n"\
          "Keeping old value depth."
        UI.messagebox msg
        depth = old_data["depth"]
      end
      data["depth"] = depth if depth && depth != 0
    end

    # Stop executing if data didn't change.
    return if data == old_data

    # Save prefix for this author so it can be suggested in the future.
    if data["id"] && data["modeler"]
      prefix = /^[^_]*/.match(data["id"])[0]
      EneBuildings.save_author_prefix data["modeler"], prefix
    end

    model = Sketchup.active_model
    model.start_operation "Saving Template Data", true

    # Remove old dictionary in case a value was changed to default and therefore
    # shouldn't be present in new data
    ad = @@component_inst.attribute_dictionary ATTR_DICT_EDITING
    @@component_inst.attribute_dictionaries.delete(ad) if ad

    # Save attributes.
    data.each_pair do |k, v|
      @@component_inst.set_attribute ATTR_DICT_EDITING, k, v
    end

    # Update ComponentDefinition name to make it correspond to ID.
    # If ID changes buildings using the template by the old ID should no longer use
    # this component definition for drawing.
    unless data["id"] == old_data["id"]
      name = Template::COMPONENT_NAME_PREFIX + id
      @@component_inst.definition.name = name
    end

    model.commit_operation

    nil

  end

  # Save part attributes from part info dialog.
  #
  # Called when closing dialog, saving template and from observer when selection
  # changes. By not calling this on each change in the dialog the undo stack is
  # prevented from being cluttered.
  #
  # Returns nothing.
  def self.save_part_data

    return unless @@part
    return if @@part.deleted?

    # Get data already saved.
    old_data = EneBuildings.attr_dict_to_hash(@@part, Template::ATTR_DICT_PART)

    # Get settings from dialog.
    # If a length starts with ~, assume it was the old length that got rounded
    # when written to form and keep old value as it is (without rounding).
    # Silently correct certain input by negate numbers or keep old value.
    # Notify user when input cannot be parsed as length and keep old value.
    data = {}
    name = @@dlg_part.get_element_value "name"
    data["name"] = unique_part_name(@@part, name) unless name.empty?
    case @@dlg_part.get_element_value "position_method"
    when "spread"
      margin = @@dlg_part.get_element_value("margin")
      begin
        margin = margin.start_with?("~") ? old_data["margin"] : margin.to_l
      rescue ArgumentError
        msg =
          "'#{margin}' could not be parsed as length.\n"\
          "Keeping old value for margin."
        UI.messagebox msg
        margin = old_data["margin"] || 0
      end
      data["margin"] = margin unless margin == 0
      margin_r = @@dlg_part.get_element_value("margin_right")
      unless margin_r.empty?
        begin
          margin_r = margin_r.start_with?("~") ? old_data["margin_right"] : margin_r.to_l
        rescue ArgumentError
          msg =
            "'#{margin_r}' could not be parsed as length.\n"\
            "Keeping old value for right margin."
          UI.messagebox msg
          margin_r = old_data["margin_right"] || margin
        end
        data["margin_right"] = margin_r unless margin_r == margin
      end
      if @@dlg_part.get_element_value("spread_fix_number") == "true"
        sp = @@dlg_part.get_element_value("spread_int").to_i
        sp = -sp if sp < 0
      else
        sp = @@dlg_part.get_element_value("spread_distance")
        begin
          sp = sp.start_with?("~") ? old_data["spread"] : sp.to_l
        rescue ArgumentError
          msg =
            "'#{sp}' could not be parsed as length.\n"\
            "Keeping old value for spread interval."
          UI.messagebox msg
          sp = old_data["spread"] || 1.m
        end
        sp = old_data["spread"] unless sp > 0
      end
      data["spread"] = sp if sp
      rounding = @@dlg_part.get_element_value("rounding")
      data["rounding"] = rounding unless rounding.empty?
    when "left", "right", "center"
      data["align"] = @@dlg_part.get_element_value "position_method"
    when "percentage"
      data["align"] = @@dlg_part.get_element_value("align_percentage").gsub(",",".").to_f
    when "gable"
      data["gable"] = true
      gable_margin = @@dlg_part.get_element_value("gable_margin")
      begin
        gable_margin = gable_margin.start_with?("~") ? old_data["gable_margin"] : gable_margin.to_l
      rescue ArgumentError
        msg =
          "'#{gable_margin}' could not be parsed as length.\n"\
          "Keeping old value for margin."
        UI.messagebox msg
        gable_margin = old_data["gable_margin"] || 0
      end
      data["gable_margin"] = gable_margin unless gable_margin == 0
      unless data["name"]
         data["name"] = unique_part_name(@@part, "Gable")
         msg = "Gable must have a name.\nUsing '#{data["name"]}."
         UI.messagebox msg
      end
    when "corner"
      data["corner"] = true
      corner_margin = @@dlg_part.get_element_value("corner_margin")
      begin
        corner_margin = corner_margin.start_with?("~") ? old_data["corner_margin"] : corner_margin.to_l
      rescue ArgumentError
        msg =
          "'#{corner_margin}' could not be parsed as length.\n"\
          "Keeping old value for margin."
        UI.messagebox msg
        corner_margin = old_data["corner_margin"] || 0
      end
      data["corner_margin"] = corner_margin unless corner_margin == 0
      unless data["name"]
         data["name"] = unique_part_name(@@part, "Corner")
         msg = "Corner must have a name.\nUsing '#{data["name"]}."
         UI.messagebox msg
      end
    end
    data["override_cut_planes"] = true if @@dlg_part.get_element_value("override_cut_planes") == "true"
    data["replace_nested_mateials"] = true if @@dlg_part.get_element_value("replace_nested_mateials") == "true"
    solid = @@dlg_part.get_element_value("solid")
    data["solid"] = solid unless solid.empty?
    solid_index = @@dlg_part.get_element_value("solid_index").to_i
    data["solid_index"] = solid_index unless solid_index.zero?

    # Stop executing if data didn't change.
    return if data == old_data

    model = @@part.model
    model.start_operation "Saving Part Data", true

    # Remove old dictionary in case a value was changed to default and therefore
    # shouldn't be present in new data.
    ad = @@part.attribute_dictionary Template::ATTR_DICT_PART
    @@part.attribute_dictionaries.delete(ad) if ad

    # Save attributes.
    data.each_pair do |k, v|
      @@part.set_attribute Template::ATTR_DICT_PART, k, v
    end

    model.commit_operation

    nil

  end

  # Show documentation in web browser.
  #
  # Returns nothing.
  def self.show_docs

    path = File.join "file:///", PLUGIN_DIR, "docs", "template_editor.html"
    UI.openURL path

    nil

  end

  # Create a name that is unique for a part in same drawing context.
  #
  # part     - The part (Group or ComponentInstance) to create the name for.
  #            Exclude this part when loocking for name collisions.
  # basename - The approximate name to use. Add incrementing number if taken.
  #
  # Returns String name.
  def self.unique_part_name(part, basename)
  
    entities = part.parent.entities
    taken_names = entities.map do |e|
      next if e == part
      next unless [Sketchup::Group, Sketchup::ComponentInstance].include? e.class
      e.get_attribute Template::ATTR_DICT_PART, "name"
    end
    taken_names.compact!
    
   basename = basename.sub(/ #\d+$/, "")
    
    name = basename
    i = 1
    while taken_names.include? name
      name = "#{basename} ##{i}"
      i += 1
    end
    
    name
    
  end
  
end

end
