# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

file = __FILE__
unless file_loaded? file
  file_loaded file

  # Context menu for select tool.
  UI.add_context_menu_handler do |menu|
    if b = Building.get_from_selection
      menu.add_separator
      menu.add_item("Building Position") { Sketchup.active_model.select_tool BuildingPositionTool.new(b) }
      menu.add_item("Building Properties") { b.properties_panel }
    end
    if TemplateEditor.active_template_component
      menu.add_separator
      item = menu.add_item("Template Info") { TemplateEditor.info_toggle }
      menu.set_validation_proc(item) { TemplateEditor.info_opened? ? MF_CHECKED : MF_UNCHECKED }
      if TemplateEditor.inside_template_component
        item = menu.add_item("Part Info") { TemplateEditor.part_info_toggle }
        menu.set_validation_proc(item) { TemplateEditor.part_info_opened? ? MF_CHECKED : MF_UNCHECKED }
      end
    end
  end

  # Menu bar.
  menu = UI.menu("Plugins").add_submenu NAME

  item = menu.add_item("Add Building") { Sketchup.active_model.select_tool BuildingInsertTool.new }
  menu.set_validation_proc(item) { TemplateEditor.inside_template_component ? MF_GRAYED : MF_ENABLED }
  item = menu.add_item("Building Position") { Sketchup.active_model.select_tool BuildingPositionTool.new }
  menu.set_validation_proc(item) { TemplateEditor.inside_template_component ? MF_GRAYED : MF_ENABLED }
  item = menu.add_item("Building Properties") { Building.get_from_selection.properties_panel }
  menu.set_validation_proc(item) { Building.selection_is_building? ? MF_ENABLED : MF_GRAYED }

  menu.add_separator
  t_menu = menu.add_submenu "Template Editing"

  item = t_menu.add_item("New") { TemplateEditor.new }
  t_menu.set_validation_proc(item) { TemplateEditor.new_available? ? MF_ENABLED : MF_GRAYED }
  item = t_menu.add_item("Open...") { TemplateEditor.open }
  t_menu.set_validation_proc(item) { TemplateEditor.inside_template_component ? MF_GRAYED : MF_ENABLED }
  t_menu.add_item("Save") { TemplateEditor.save }
  item = t_menu.add_item("Template Info") { TemplateEditor.info_toggle }
  t_menu.set_validation_proc(item) { TemplateEditor.info_opened? ? MF_CHECKED : MF_UNCHECKED }
  item = t_menu.add_item("Part Info") { TemplateEditor.part_info_toggle }
  t_menu.set_validation_proc(item) { TemplateEditor.part_info_opened? ? MF_CHECKED : MF_UNCHECKED }
  t_menu.add_separator

  item = t_menu.add_item("Manually Downsample Previews") { Template.manually_resize_previews = !Template.manually_resize_previews }
  t_menu.set_validation_proc(item) { Template.manually_resize_previews ? MF_CHECKED : MF_UNCHECKED }
  item = t_menu.add_item("Update Previewss on Save") { TemplateEditor.update_previes = !TemplateEditor.update_previes }
  t_menu.set_validation_proc(item) { TemplateEditor.update_previes ? MF_CHECKED : MF_UNCHECKED }

  t_menu.add_separator
  t_menu.add_item("Open Template Directory") { Template.open_dir }
  t_menu.add_item("Documentation") { TemplateEditor.show_docs }

  # Toolbar.
  tb = UI::Toolbar.new NAME

  cmd = UI::Command.new("Add Building") { Sketchup.active_model.select_tool BuildingInsertTool.new }
  cmd.large_icon = "toolbar_icons/building_insert.png"
  cmd.small_icon = "toolbar_icons/building_insert_small.png"
  cmd.tooltip = "Add Building"
  cmd.status_bar_text = "Draw new building to model."
  cmd.set_validation_proc { TemplateEditor.inside_template_component ? MF_GRAYED : MF_ENABLED }
  tb.add_item cmd

  cmd = UI::Command.new("Building Position") { Sketchup.active_model.select_tool BuildingPositionTool.new }
  cmd.large_icon = "toolbar_icons/building_position.png"
  cmd.small_icon = "toolbar_icons/building_position_small.png"
  cmd.tooltip = "Building Position"
  cmd.status_bar_text = "Reposition building by changing their path and end angles."
  cmd.set_validation_proc { TemplateEditor.inside_template_component ? MF_GRAYED : MF_ENABLED }
  tb.add_item cmd

  cmd = UI::Command.new("Building Properties") { Building.get_from_selection.properties_panel }
  cmd.large_icon = "toolbar_icons/building_properties.png"
  cmd.small_icon = "toolbar_icons/building_properties_small.png"
  cmd.tooltip = "Building Properties"
  cmd.status_bar_text = "Open properties window for selected building."
  cmd.set_validation_proc { Building.selection_is_building? ? MF_ENABLED : MF_GRAYED }
  tb.add_item cmd

  tb.show

  # Template Toolbar (separate so non-advanced users can hide it).
  tb = UI::Toolbar.new "#{NAME} Template Editing"

  cmd = UI::Command.new("New Template") { TemplateEditor.new }
  cmd.large_icon = "toolbar_icons/template_new.png"
  cmd.small_icon = "toolbar_icons/template_new_small.png"
  cmd.tooltip = "New Template"
  cmd.status_bar_text = "Create a new template component from the selected entities."
  cmd.set_validation_proc { TemplateEditor.new_available? ? MF_ENABLED : MF_GRAYED }
  tb.add_item cmd

  cmd = UI::Command.new("Open Template...") { TemplateEditor.open }
  cmd.large_icon = "toolbar_icons/template_open.png"
  cmd.small_icon = "toolbar_icons/template_open_small.png"
  cmd.tooltip = "Open Template..."
  cmd.status_bar_text = "Load template component from library for editing."
  cmd.set_validation_proc { TemplateEditor.inside_template_component ? MF_GRAYED : MF_ENABLED }
  tb.add_item cmd

  cmd = UI::Command.new("Save Template") { TemplateEditor.save }
  cmd.large_icon = "toolbar_icons/template_save.png"
  cmd.small_icon = "toolbar_icons/template_save_small.png"
  cmd.tooltip = "Save Template"
  cmd.status_bar_text = "Save template component to library."
  tb.add_item cmd

  tb.add_separator

  cmd = UI::Command.new("Template Info") { TemplateEditor.info_toggle }
  cmd.large_icon = "toolbar_icons/template_info.png"
  cmd.small_icon = "toolbar_icons/template_info_small.png"
  cmd.tooltip = "Template Info"
  cmd.status_bar_text = "Set template information such as name, ID and built year."
  cmd.set_validation_proc { TemplateEditor.info_opened? ? MF_CHECKED : MF_UNCHECKED }
  tb.add_item cmd

  cmd = UI::Command.new("Part Info") { TemplateEditor.part_info_toggle }
  cmd.large_icon = "toolbar_icons/template_part_info.png"
  cmd.small_icon = "toolbar_icons/template_part_info_small.png"
  cmd.tooltip = "Part Information"
  cmd.status_bar_text = "Set part information such as positioning within building."
  cmd.set_validation_proc { TemplateEditor.part_info_opened? ? MF_CHECKED : MF_UNCHECKED }
  tb.add_item cmd

  tb.show

end

end

