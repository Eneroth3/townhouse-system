# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

# Internal: Tool for inserting buildings.
class BuildingInsertTool

  include PathHandling

  MSG_NO_TEMPLATE = "A template must be selected before path can be drawn."

  STATUS_NO_TEMPLATE = "Select a template from list."
  STATUS_PATH        = "Click to add point. Double click or Enter = Draw Building."

 # Template to draw building to.
 # Class variable so it's kept when tool is reactivated.
 @@template ||= nil

  def initialize

    # Initialize path handler.
    super([], true, [0, 0], Template::FALLBACK_DEPTH, true, false)

    # Web dialog to select building template from.
    init_dlg

    @ph = Sketchup.active_model.active_view.pick_helper

  end

  # Sketchup tool interface.

  def activate

    Sketchup.active_model.active_view.invalidate

    Sketchup.status_text = @@template ? STATUS_PATH : STATUS_NO_TEMPLATE

  end

  def deactivate(view)

    # Close template selector when deactivating tool.
    @dlg.close

    view.invalidate

  end

  def draw(*)

    super if @@template

  end

  def getExtents(*)

    super if @@template

  end

  def getInstructorContentDirectory

    File.join PLUGIN_DIR, "docs", "instructors", "building_insert_tool.html"

  end

  def getMenu(*args)
    menu, flags, x, y, view = args

    # Forward to path handler.
    super if @@template

    # Add menu entries unique for this tool.
    menu.add_separator if @@template

    item = menu.add_item("Templates") { @dlg.visible? ? @dlg.close : init_dlg }
    menu.set_validation_proc(item) { @dlg.visible? ? MF_CHECKED : MF_UNCHECKED }

    @ph.do_pick(x, y)
    e = @ph.best_picked
    if Building.group_is_building? e
      b = Building.new e
      menu.add_item("Pick Template") { set_template b.template}
    end

    true# If return value is falsy menu wont work at all.

  end

  def onCancel(reason, view)

    reason == 0 ? @path.pop : @path = []
    @reset
    view.invalidate

  end

  def onKeyUp(*)

    super if @@template

  end

  def onLButtonDoubleClick(*)

    insert_building

  end

  def onLButtonDown(*)

    if @@template
      super
    else
      UI.messagebox MSG_NO_TEMPLATE
      @dlg.visible? ? @dlg.bring_to_front : init_dlg
    end

  end

  def onLButtonUp(*)

    super if @@template

  end

  def onMouseMove(*)

    super if @@template

  end

  def onReturn(*)

    # Pressing enter saves currently positioned building and returns to select
    # mode.
    insert_building if @@template && !@path.empty?

  end

  def onSetCursor

    if @@template
      super
    else
      UI.set_cursor CURSOR_PEN_INVALID
    end

  end

  def resume(view)

    super if @@template

    Sketchup.status_text = @@template ? STATUS_PATH : STATUS_NO_TEMPLATE
    view.invalidate

  end

  # Internal methods.
  private

  # Creates web dialog for select panel and save reference as @dlg.
  def init_dlg
    @dlg = Template.select_panel("Select Template", @@template, true) do |t|
      @@template = t
      @handle_length = t.depth || Template::FALLBACK_DEPTH
      Sketchup.active_model.active_view.invalidate
    end
  end

  # Draw building to @path using @template.
  # Called when pressing enter.
  def insert_building

  Sketchup.active_model.start_operation "Add Building", true

  b                 = Building.new
  b.template        = @@template
  b.path            = @path
  b.back_along_path = @back_along_path
  b.end_angles      = @end_angles
  b.draw

  @path = []
  @end_angles = [0, 0]
  @reset

  Sketchup.active_model.commit_operation

  end

  # Set template (from right clicking other building) and update web dialog
  def set_template(t)

    @@template = t
    @handle_length = t.depth || Template::FALLBACK_DEPTH
    Sketchup.active_model.active_view.invalidate
    @dlg.close
    init_dlg

  end

end# Class

end# Module
