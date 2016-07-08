# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

# Internal: Various draw methods for View.
# REVIEW: Should typically be a refinement to Sketchup::View.
module MyView

  # Draw arrow tip.
  # REVIEW: Currently can't point straight upwards or downwards.
  def self.draw_arrow_head(view, point, vector, width, depth, centered = false)
    
    path = [
      Geom::Point3d.new(-depth, -width/2, 0),
      Geom::Point3d.new(0, 0, 0),
      Geom::Point3d.new(-depth, width/2, 0),
    ]
    
    path.each { |p| p.x += depth/2 } if centered
    
    trans = Geom::Transformation.axes point, vector, vector*Z_AXIS, vector*Z_AXIS*vector
    path.each { |p| p.transform! trans }
    
    view.draw GL_LINE_STRIP, path
    
  end
  
  # Draw 3d box to viewport.
  # Side as a Length.
  # Omit colors to skip edge or fill drawing.
  def self.draw_box(view, point, side, border_color, fill_color, on_top = false, x_axis = X_AXIS, z_axis = Z_AXIS)

    y_axis = z_axis * x_axis
    d = side/2

    pts = [point.offset(x_axis, d), point.offset(x_axis, -d)].map do |i|
      [i.offset(y_axis, d), i.offset(y_axis, -d)].map do |j|
        [j.offset(z_axis, d), j.offset(z_axis, -d)]
      end
    end
    pts.flatten!
    pts = pts.map { |p| view.screen_coords p } if on_top

    lines = [
      pts[0], pts[1],
      pts[0], pts[2],
      pts[0], pts[4],
      pts[1], pts[3],
      pts[1], pts[5],
      pts[2], pts[3],
      pts[2], pts[6],
      pts[3], pts[7],
      pts[4], pts[5],
      pts[4], pts[6],
      pts[5], pts[7],
      pts[6], pts[7]
    ]

    quads = [
      pts[0], pts[1], pts[3], pts[2],
      pts[0], pts[2], pts[6], pts[4],
      pts[0], pts[4], pts[5], pts[1],
      pts[7], pts[3], pts[1], pts[5],
      pts[7], pts[6], pts[2], pts[3],
      pts[7], pts[5], pts[4], pts[6],
    ]

    if fill_color
      view.drawing_color = fill_color
      if on_top
        view.draw2d GL_QUADS, quads
      else
        view.draw GL_QUADS, quads
      end
    end

    if border_color
      view.drawing_color = border_color
      if on_top
        view.draw2d GL_LINES, lines
      else
        view.draw GL_LINES, lines
      end
    end

  end

  # Draw a 2d circle to viewport.
  # Diameter in px.
  # Omit colors to skip edge or fill drawing.
  def self.draw_circle(view, point, diameter, border_color = nil, fill_color = nil)

    point = view.screen_coords point

    # Each segment is 4 px long
    radius = 0.5*diameter
    segments = (Math::PI*radius/2).floor
    segments = 3 if segments < 3

    path = (0..segments - 1).map do |i|
      a = 2*Math::PI*i/segments
      x = Math.cos(a)*radius
      y = Math.sin(a)*radius
      point.offset([x, y, 0])
    end

    if fill_color
      view.drawing_color = fill_color
      view.draw2d GL_POLYGON, path
    end

    if border_color
      view.drawing_color = border_color
      view.draw2d GL_LINE_LOOP, path
    end

    nil

  end

  # Draw 3d cylinder to viewport.
  # Diameter as a Length.
  # Omit colors to skip edge or fill drawing.
  def self.draw_cylinder(view, point, diameter, border_color, fill_color, on_top = false, axis = Z_AXIS, height = nil)
    height ||= diameter

    radius = diameter*0.5

    # Center of top circle.
    center = point.offset axis, 0.5 * height

    # Segment count should be divisible with 2.
    segments = [((diameter/view.pixels_to_model(1, point)/2).ceil*2), 4].max

    # Top and bottom polygons (should look like circles).
    top_path = (0..segments - 1).map do |i|
      a = 2 * Math::PI * i/segments
        t = Geom::Transformation.rotation ORIGIN, axis, a
        v = t.xaxis
        center.offset v, radius
    end
    bottom_path = top_path.map { |c| c.offset axis, -height }

    # Find indexes of corners for contours.
    # Use those furthest from center in 2d perspective.
    distances_2d = (0..segments - 1).map do |i|
      center_2d = view.screen_coords center
      center_2d.z = 0
      p_2d = view.screen_coords top_path[i]
      p_2d.z = 0
      center_2d.distance p_2d
    end
    contour0 = distances_2d.index distances_2d.max
    contour1 = (contour0 + (segments/2))%segments

    # If on top, start using 2d coordinates from now.
    if on_top
      top_path = top_path.map { |p| view.screen_coords p }
      bottom_path = bottom_path.map { |p| view.screen_coords p }
    end

    # Contours, the 2 lines furthest from center in 2d perspective.
    contours = [
      top_path[contour0],
      bottom_path[contour0],
      top_path[contour1],
      bottom_path[contour1]
    ]

    # Cylindrical face as quads.
    quads = []
    (0..segments - 1).each do |i|
      quads << top_path[i]
      quads << top_path[i - 1]
      quads << bottom_path[i - 1]
      quads << bottom_path[i]
    end

    if fill_color
      view.drawing_color = fill_color
      if on_top
        view.draw2d GL_QUADS, quads
        view.draw2d GL_POLYGON, top_path
        view.draw2d GL_POLYGON, bottom_path
      else
        view.draw GL_QUADS, quads
        view.draw GL_POLYGON, top_path
        view.draw GL_POLYGON, bottom_path
      end
    end

    if border_color
      view.drawing_color = border_color
      if on_top
        view.draw2d GL_LINE_LOOP, top_path
        view.draw2d GL_LINE_LOOP, bottom_path
        view.draw2d GL_LINES, contours
      else
        view.draw GL_LINE_LOOP, top_path
        view.draw GL_LINE_LOOP, bottom_path
        view.draw GL_LINES, contours
      end
    end

  end

  # Draw 2d square to viewport.
  # Side in px.
  # Omit colors to skip edge or fill drawing.
  def self.draw_square(view, point, side, border_color = nil, fill_color = nil)

    if fill_color
      view.draw_points([point], side, 2, fill_color)
    end

    if border_color
      view.draw_points [point], side, 1, border_color
    end

    nil

  end

  # Relocate camera to fit content.
  # Similar to View.zoom or View.zoom_extents but handels camera's aspect_ratio
  # ratio and allows for custom angles.
  #
  # view     - The view whose camera should be moved.
  # content  - The content to fit defined as Entities, Entity object, Point3d
  #            objects or an Array of Entity objects and Point3d objects.
  # margin   - Percentage of viewport to keep clean of content on each side
  #            (default: 0.025).
  #            (default: whole model).
  # h_angle  - The horizontal camera angle (default: current camera's).
  # v_angle  - The vertical camera angle (default: current camera's).
  #
  # When angles are not set they are taken from the current camera.
  def self.zoom_content(view, content = nil, margin = 0.025, h_angle = nil, v_angle = nil)
  
    model = view.model
    cam = view.camera
    
    unless cam.perspective?
      raise "Method only supported for perspective projection."
    end
    
    # Points to fit in view.
    content ||= model.active_entities
    unless [Array, Sketchup::Entities].include? content.class
      content = [content]
    end
    if content.is_a? Array
      pts     = content.select { |p| p.is_a? Geom::Point3d }
      content -= pts
      pts     += EneBuildings.points_in_entities content
    else
      pts     = EneBuildings.points_in_entities content
    end
    
    # Get frustum angles from current camera if arguments are not given.
    ratio   = cam.aspect_ratio
    ratio   = view.vpwidth.to_f/view.vpheight if ratio == 0
    if cam.fov_is_height?
      v_angle ||= cam.fov.degrees
      h_angle ||= Math.atan(Math.tan(v_angle/2)*ratio)*2
    else
      h_angle ||= cam.fov.degrees
      v_angle ||= Math.atan(Math.tan(h_angle/2)/ratio)*2
    end

    # Decrease angles for a small margin around the content.
    # Margin is a percentage of viewing plane, not angle.
    ###h_angle /= (1+2*margin)
    ###v_angle /= (1+2*margin)
    v_angle = Math.atan(Math.tan(v_angle/2)*(1-margin*2))*2
    h_angle = Math.atan(Math.tan(h_angle/2)*(1-margin*2))*2

    # Get frustum planes.
    # Top, bottom, left, right.
    sight_vector = cam.target - cam.eye
    side_vector  = sight_vector*cam.up
    transformations = [
      Geom::Transformation.rotation(ORIGIN, side_vector, 90.degrees + v_angle/2),
      Geom::Transformation.rotation(ORIGIN, side_vector, -90.degrees - v_angle/2),
      Geom::Transformation.rotation(ORIGIN, cam.up, 90.degrees + h_angle/2),
      Geom::Transformation.rotation(ORIGIN, cam.up, -90.degrees - h_angle/2)
    ]
    frustum_planes = transformations.map { |t| [cam.eye, sight_vector.transform(t)] }

    # Move each plane onto outermost point in each direction to cover all points.
    frustum_planes.each do |plane|
      outermost_point = pts.sort_by { |p| MyGeom.distance_to_plane(p, plane) }.last
      plane[0] = outermost_point
    end
    
    # Get camera eye point.
    # Intersect opposite frustum planes and find point on the furthest back
    # intersection line where it's closest to other intersection line.
    intersection_lines = [
      Geom.intersect_plane_plane(frustum_planes[0], frustum_planes[1]),
      Geom.intersect_plane_plane(frustum_planes[2], frustum_planes[3])
    ]
    closest_points = Geom.closest_points(intersection_lines[0], intersection_lines[1])
    eye = closest_points.sort_by { |p| MyGeom.distance_to_plane(p, [cam.eye, sight_vector]) }.first
    cam.set(eye, eye + sight_vector, cam.up)
    
    nil
  
  end
  
end

end