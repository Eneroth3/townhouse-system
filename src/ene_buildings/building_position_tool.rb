# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

# Internal: Tool for repositioning buildings.
class BuildingPositionTool

  include PathHandling

  STATUS_SELECT = "Click a building to reposition."
  STATUS_PATH   = "Enter = Save position, Esc = Cancel."

  def initialize(building = nil)

    #If not initialized with a building, see if selection is one.
    building ||= Building.get_from_selection

    # Initialize path handler.
    super()

    # building being repositioned. When nil user can select a building similar to
    # how scale, move and rotate tools enables user to select geometry.
    # Set in start_reposition
    @building

    start_reposition building if building

    @ph = Sketchup.active_model.active_view.pick_helper

  end

  # Sketchup tool interface.

  def activate

    Sketchup.active_model.active_view.invalidate

    Sketchup.status_text = @building ? STATUS_PATH : STATUS_SELECT

  end

  def deactivate(*)

    # Save currently positioned building if any.
    commit_reposition if @building

  end

  def draw(*)

    super if @building

  end

  def getExtents(*)

    super if @building

  end

  def getInstructorContentDirectory

    File.join PLUGIN_DIR, "docs", "instructors", "building_position_tool.html"

  end

  def getMenu(*)

    super if @building

    true

  end

  def onCancel(*)

    # Abort building operation when canceling.
    abort_reposition if @building

  end

  def onLButtonDown(*args)
    flags, x, y, view = args

    if @building
      # When a building is being repositioned, forward to path_handler.

      super

    else
      # Otherwise in select mode.
      # Click building to start reposition it.

      @ph.do_pick(x, y)
      e = @ph.best_picked
      if Building.group_is_building? e
        start_reposition Building.new e
      end

    end

  end

  def onLButtonUp(*)

    super if @building

  end

  def onKeyUp(*args)

    super if @building

  end

  def onMouseMove(*args)
    flags, x, y, view = args

    if @building
      # When a building is being repositioned, forward to path_handler.

      super

    else
      # Otherwise in select mode.
      # Highlight hovered building if any.

      selection = Sketchup.active_model.selection
      selection.clear

      @ph.do_pick(x, y)
      e = @ph.best_picked
      selection.add e if Building.group_is_building? e

    end


  end

  def onReturn(*)

    # Pressing enter saves currently positioned building and returns to select
    # mode.
    commit_reposition if @building

  end

  def onSetCursor

    if @building
      super
    else
      UI.set_cursor CURSOR_ARROW
    end

  end

  def resume(view)

    super if @building

    Sketchup.status_text = @building ? STATUS_PATH : STATUS_SELECT
    view.invalidate

  end

  # Internal methods.
  private

  def abort_reposition

    # Abort operation, restoring building.
    Sketchup.active_model.abort_operation

    # Return to select mode.
    @building  = nil
    Sketchup.active_model.active_view.invalidate

    Sketchup.status_text = STATUS_SELECT

    nil

  end

  def commit_reposition
  
    # OPTIMIZE: If path is same as it was on reposition start, just abort instead.

    # Draw building to new path.
    @building.path            = @path
    @building.back_along_path = @back_along_path
    @building.end_angles      = @end_angles
    @building.draw

    Sketchup.active_model.commit_operation

    # Return to select mode.
    @building  = nil
    Sketchup.active_model.active_view.invalidate

    Sketchup.status_text = STATUS_SELECT

    nil

  end

  def start_reposition(building)

    # Check if building has a template.
    # If not stop execution and call method again once user has chose one.
    return unless building.valid_template? { start_reposition(building) }

    @building = building

    # Empty selection so Del key can be safely used without deleting entities.
    Sketchup.active_model.selection.clear

    # Start operation and empty building group so path can be viewed.
    Sketchup.active_model.start_operation "Reposition Building", true
    @building.group.entities.clear!

    @path            = @building.path
    @back_along_path = @building.back_along_path
    @end_angles      = @building.end_angles
    @handle_length   = @building.template.depth || Template::FALLBACK_DEPTH
    Sketchup.active_model.active_view.invalidate

    Sketchup.status_text = STATUS_PATH

    nil

  end

end

end
