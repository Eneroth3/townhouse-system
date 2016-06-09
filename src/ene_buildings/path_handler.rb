# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

# Internal: Class to handle path creation and reposition.
# Not directly activated as a tool but called from actual tools' methods.
#
# Since several tools will handle paths in a very similar way the code handling
# paths is written in this external class. An object of this class is created
# when tool is initialized with some information how it should behave.
#
# Methods in tool can then both contain their own code and forward their
# arguments to the corresponding method in this class. Just inheriting this
# class wouldn't allow for other different code to run in each tool.
#
# Finally the path can be returned back to the actual tool that does something
# with it, e.g. draw a new house a position an existing according to it.
class PathHandler

  COLOR_PATH              = Sketchup::Color.new 255, 255,   0
  COLOR_PATH_NEW          = Sketchup::Color.new 255, 255,   0, 127
  COLOR_CONTROLLER        = Sketchup::Color.new   0, 255,   0
  COLOR_ACTIVE_CONTROLLER = Sketchup::Color.new 255,   0,   0
  COLOR_CONTROLLER_EDGES  = Sketchup::Color.new   0,   0,   0
  COLOR_PROJECTION        = Sketchup::Color.new 128, 128, 128

  PATH_WIDTH = 3

  SNAP_TRESHOLD = 12
  DRAG_TRESHOLD = 4

  CONTROLLER_SIZE       = 10
  CONTROLLER_MIN_LENGTH = 0.1# It seems like scale tool uses a min size of 0.1".

  GRAPHICAL_ANGLES = [-90.degrees, 90.degrees]
  HANDLE_LENGTH = 10.m
  
  

  TOOLTIPS = {
    :add_interior  => "Add Corner on Segment",
    :select_corner => "Move or Delete Corner",# hover corner.
    :select_angle => "Change End Angle"# hover end angle controller.
  }

  # Get or set path being edited.
  attr_accessor :path

  # Get or set end angles being edited.
  attr_accessor :end_angles
  
  # Get or set end angle handler length.
  # If set to nil default length is used.
  attr_reader :handle_length
  def handle_length=(v) @handle_length = v || HANDLE_LENGTH end

  # Internal: Create instance of the path handler.
  # Typically this is done when initializing tool and reference is saved to
  # @path_handler.
  #
  # path             - The path to start with (default: empty array).
  # add_point_mode   - When true tool lets user add point to end of path when
  #                    clicking outside existing path. When false nothing
  #                    happens when clicking outside existing path.
  #                    Can also be toggled from context menu (default: false).
  # end_angles       - Array containing angle for each house end or nil when
  #                    end angles cannot be set.
  # handle_length    - Distance from path to angle handles.
  # force_horizontal - Force path to be horizontal by placing all point on the
  #                    same z coordinate as first point (default: true).
  def initialize(path = [], add_point_mode = false, end_angles = nil, handle_length = HANDLE_LENGTH, force_horizontal = true)# TODO: use hash for all arguments?

    @path             = path
    @add_point_mode   = add_point_mode
    @end_angles       = end_angles
    @handle_length    = handle_length
    @force_horizontal = force_horizontal

    # What controller is currently selected (being moved)
    # Index to the point in path currently selected, :start,
    # :end or nil when nothing is selected.
    @active_controller

    # What controller or path segment is hovered.
    # As @active_controller but negative index is used when path is hovered
    # between corners. Segment cannot be selected though, only hovered.
    @hovered_controller

    @ip = Sketchup::InputPoint.new

    # Input point position projected to planes or lines input is locked to.
    @corrected_input

    # Update controller's scaling.
    update_controller_scaling Sketchup.active_model.active_view

    # Coordinates for last mouse down.
    # Used to differ down-drag-up from click-move-click.
    @x_down
    @y_down

    # Clear model selection so delete key can be safely used.
    Sketchup.active_model.selection.clear

  end

  # Sketchup tool interface.

  def draw(view)

    view.line_width = PATH_WIDTH

    # Path
    if @path.size > 1
      view.drawing_color = COLOR_PATH
      view.draw_polyline @path
    end

    # Path segment preview.
    if !@path.empty? && @add_point_mode && @corrected_input && !@hovered_controller
      view.drawing_color = COLOR_PATH_NEW
      #view.draw_line does not support transparency.
      view.draw( GL_LINES, [@path.last, @corrected_input] )
    end

    # Path corners
    @path.each_with_index do |c, i|
      type = @hovered_controller == i ? :active : :default
      draw_controller c, view, type
    end
    if @hovered_controller.is_a?(Fixnum) && @hovered_controller >= 0
      view.tooltip = TOOLTIPS[:select_corner]
    end

    # Path (end) corner preview.
    if @corrected_input && @add_point_mode && !@hovered_controller
      draw_controller @corrected_input, view, :preview
    end

    # Path interior corner preview.
    # (When hovering segment)
    if @corrected_input && @hovered_controller.is_a?(Fixnum) && @hovered_controller < 0
      draw_controller @corrected_input, view, :preview
      view.tooltip = TOOLTIPS[:add_interior]
    end

    # Angle handles.
    if @end_angles && @path.size > 1

      ac = angle_controller_positions
      [0, 1].each do |i|
        point = ac[i]
        vector = @path[-i] - @path[1 - 3 * i]
        vector.length = @handle_length * 0.5
        t = Geom::Transformation.rotation ORIGIN, Z_AXIS, GRAPHICAL_ANGLES[i] + 90.degrees
        vector.transform! t

        view.drawing_color = COLOR_PATH
        view.line_width = PATH_WIDTH
        view.line_stipple = "_"
        view.draw_lines @path[-i], point
        if @hovered_controller.is_a? Symbol
          view.line_stipple = "."
          pts = [point.offset(vector), point.offset(vector.reverse)]
          view.draw_lines pts
          view.tooltip = TOOLTIPS[:select_angle]
        end
        view.line_stipple = ""

        status = :default
        status = :active if @hovered_controller == :start && i == 0
        status = :active if @hovered_controller == :end && i == 1
        draw_controller point, view, status, :box, vector

      end
    end

    # Draw input point if controller is being moved or new point is being added.
    if @active_controller || (@add_point_mode && !@hovered_controller)
      if @corrected_input && @ip.position != @corrected_input
        view.drawing_color = COLOR_PROJECTION
        view.line_stipple = "-"
        view.draw_line @ip.position, @corrected_input
        view.line_stipple = ""
      end
      view.tooltip = @ip.tooltip
      @ip.draw view
    end

  end

  def getExtents

    bb = Geom::BoundingBox.new
    bb.add @path unless @path.empty?

    bb

 end

  def getMenu(menu, flags, x, y, view)

    menu.add_item("Reverse Path") { @path.reverse!; view.invalidate }
    item = menu.add_item("Add to Path") { @add_point_mode = !@add_point_mode }
    menu.set_validation_proc(item) { @add_point_mode ? MF_CHECKED : MF_UNCHECKED }

  end

  def onKeyUp(key, repeat, flags, view)

      if @active_controller.is_a?(Fixnum) && key == VK_DELETE && @path.size > 2
        # A path corner was selected and user pressed delete. Remove it.

        @path.delete_at @active_controller
        @active_controller = nil
        @hovered_controller = nil
        view.invalidate

      end
  end

  def onLButtonDown(flags, x, y, view)

    @x_down, @y_down = x, y

    if @active_controller
      # A moved controller was placed.

      @active_controller = nil

    elsif @hovered_controller
      if @hovered_controller.is_a?(Symbol) || @hovered_controller >= 0
        # A controller (path corner or end vector handler) was clicked.
        # Select it.
        @active_controller = @hovered_controller
      else
        # A path segment was clicked.
        # Add point on it.
        @path.insert -@hovered_controller, @corrected_input
      end
    elsif @add_point_mode
      # No existing controller was clicked and user is in add_pont_mode.
      # Add point to end of path.

      @path << @corrected_input

    end

    view.invalidate

  end

  def onLButtonUp(flags, x, y, view)

    return if !@x_down || !@y_down

    # Check if mouse moved since it was pressed down.
    return if [x, y, 0].distance([@x_down, @y_down, 0]) < DRAG_TRESHOLD

    if @active_controller
      # A moved controller was placed

      @active_controller = nil

    end

  end

  def onMouseMove(flags, x, y, view)

    @ip.pick view, x, y
    update_corrected_input view

    if @active_controller
      # A controller is being moved.

      if @active_controller.is_a? Fixnum
        @path[@active_controller] = @corrected_input
      else
        angle_from_input
      end

    else

      # No controller moved, check if one is hovered.
      @hovered_controller = mouse_on_controller x, y, view

    end

    view.invalidate

  end

  def onSetCursor

    cursor =
      if @add_point_mode && !@active_controller && !@hovered_controller
        CURSOR_PEN
      elsif @hovered_controller.is_a?(Fixnum) && @hovered_controller < 0
        CURSOR_PEN
      else
        CURSOR_ARROW
      end

    UI.set_cursor cursor

  end

  def resume(view)

    update_controller_scaling view

  end

  # Public but outside tool interface.

  # Resets @active_controller and @hovered_controller to nil.
  # When tool is done with path handling and enters another mode (e.g. select
  # an object to edit the path of) it's good practice to reset these so the
  # path_handler doesn't refer to non existing controllers.
  def reset

    @active_controller = @hovered_controller = nil

  end

  # Internal methods.
  private

  # Returns array of 2 points representing angle controller positions.
  def angle_controller_positions

    [0, 1].map do |i|
      vector = @path[-i] - @path[1 - 3 * i]
      vector.length = @handle_length/Math.cos(@end_angles[i])
      a = @end_angles[i] + GRAPHICAL_ANGLES[i]
      vector.transform! Geom::Transformation.rotation(ORIGIN, Z_AXIS, a)

      @path[-i].offset vector
    end

  end

  # Updates angle for (between -90 degrees and +90 degrees).
  def angle_from_input

    return if @path.size < 2
    return unless @active_controller.is_a? Symbol

    i = @active_controller == :start ? 0 : 1
    corner = @path[-i]
    ref_vector = @path[-i] - @path[1 - 3 * i]
    input_vector = corner - @ip.position
    return unless input_vector.valid?
    return if input_vector.samedirection? Z_AXIS
    return if input_vector.samedirection? ref_vector

    angle = -(MyGeom.angle_in_plane input_vector, ref_vector)
    angle -= GRAPHICAL_ANGLES[i]
    angle = ((angle+90.degrees)%180.degrees)-90.degrees

    @end_angles[i] = angle

  end

  # Determines color and scale of controller and call draw method.
  #
  # status - :default - Normal path corner.
  #          :active  - Path corner being hovered or selected.
  #          :preview - Preview of path corner not yet drawn.
  # type - :box      - Draw as cube.
  #      - :cylinder - Draw as cylinder.
  #
  def draw_controller(point, view, status = :default, type = :cylinder, axis = nil)

    view.line_width = 1

    # Get size in pixels for point.
    # A point in the center of the path would be 10 px big, scale this according
    # to perspective.

    size = [CONTROLLER_SIZE * px_to_length(view), CONTROLLER_MIN_LENGTH].max
    #size_2d = CONTROLLER_SIZE * scale_factor(point, view)
    border_color = COLOR_CONTROLLER_EDGES
    fill_color = if status == :active
        COLOR_ACTIVE_CONTROLLER
      else
       status == :default ? COLOR_CONTROLLER : nil
      end
    on_top = status == :active

    if type == :box
      MyView.draw_box(view, point, size, border_color, fill_color, on_top, axis)
      #MyView.draw_square(view, point, size_2d, border_color, fill_color)
    else
      MyView.draw_cylinder(view, point, size, border_color, fill_color, on_top)
      #MyView.draw_circle(view, point, size_2d, border_color, fill_color)
    end

    nil

  end

  # Check where mouse is on path.
  #
  # Returns Fixnum index starting at 0 when mouse is on corner,
  # Fixnum index starting at -1 and counting backward when on segment,
  # :start when on start angle handle, :end when on end vector
  # handle and nil when not on any of these.
  def mouse_on_controller x, y, view

    mouse = [x, y, 0]

    # Path corners.
    @path.each_with_index do |c, i|
      c2d = view.screen_coords c
      c2d.z = 0
      return i if c2d.distance(mouse) < SNAP_TRESHOLD * scale_factor(c, view)
    end

    # Path segments.
    eye = view.camera.eye
    line_to_cam = [eye, eye - @ip.position]
    (0..@path.size - 2).each do |i|
      c0 = @path[i]
      c1 = @path[i + 1]
      segment_line = [c0, c1 - c0]
      # Get point on segment's line closest to mouse.
      point_on_segment = Geom.closest_points(segment_line, line_to_cam).first
      next if c0.distance(point_on_segment) > c0.distance(c1)
      next if c1.distance(point_on_segment) > c1.distance(c0)
      point_on_segment_2d = view.screen_coords point_on_segment
      return -(i + 1) if point_on_segment_2d.distance(mouse) < SNAP_TRESHOLD
    end

    # End angle handles.
    if @end_angles && @path.size > 1
      angle_controller_positions.each_with_index do |p, i|
        p2d = view.screen_coords p
        p2d.z = 0
        if p2d.distance(mouse) < SNAP_TRESHOLD * scale_factor(p, view)
          return i == 0 ? :start : :end
        end
      end
    end

    nil

  end

  # Get float telling model length of a pixel at path center point.
  def px_to_length(view)

    view.pixels_to_model 1, @scale_origin

  end

  # Get float telling how much point is scaled in perspective relative to path
  # center point.
  def scale_factor(point, view)

    px_to_length(view)/view.pixels_to_model(1, point)

  end

  # Finds centroid of path.
  # controllers are scaled relative to perspective as if they had a predefined
  # size in this point.
  # Updated on initialize and when resuming tool so controllers don't scale on
  # mouse move.
  def update_controller_scaling(view)

    @scale_origin =
      if @path.empty?
        @ip.position
      else
        bb = Geom::BoundingBox.new
        bb.add @path
        bb.center
      end

    nil

  end

  # Projects input point position to whatever it's currently locked to.
  def update_corrected_input(view)

    eye = view.camera.eye
    line_to_cam = [eye, eye - @ip.position]

    @corrected_input =
      if !@active_controller && @hovered_controller.is_a?(Symbol)
        # A end vector handle is hovered.
        ## TODO: remove this block. angle handlers do not use this method anyway. also clean up code in general.

      elsif !@active_controller && @hovered_controller && @hovered_controller < 0
        # A path segment is hovered.
        # Correct point so it's on the path.
        c0 = @path[-@hovered_controller - 1]
        c1 = @path[-@hovered_controller]
        segment_line = [c0, c1 - c0]
        point_on_segment = Geom.closest_points(segment_line, line_to_cam).first
        point_on_segment

      elsif (@add_point_mode || @active_controller) && @force_horizontal
        # Adding point to end of path or moving path corner,
        # and path is locked to horizontal.
        # Make sure it has correct z coordinate.

        plane = [@path[0], Z_AXIS]
        if @path.empty?
          @ip.position
        elsif @ip.degrees_of_freedom == 3
          Geom.intersect_line_plane line_to_cam, plane
        else
          @ip.position.project_to_plane plane
        end

      else
        # No correction
        @ip.position
      end

    nil

  end

end# Class

end# Module
