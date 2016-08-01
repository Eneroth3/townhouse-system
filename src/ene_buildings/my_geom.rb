# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

# Internal: Various geometrical methods.
# REVIEW: Should typically be a refinement to Geom.
module MyGeom

  # Get angle cc from v0 to v1 seen from normal.
  #
  # v0     - First vector.
  # v1     - Second vector.
  # normal - Normal of the plane to check the angle in.
  #
  # Returns angle in radians.
  def self.angle_in_plane(v0, v1, normal = Z_AXIS)

    #Flatten to plane.
    v0 = flatten_vector v0, normal
    v1 = flatten_vector v1, normal

    #Get angle size.
    a = v0.angle_between v1

    return a if v0.parallel? v1

    #Get angle direction.
    a *= -1 if (v1 * v0).samedirection? normal

    a

  end

  # Returns array of all bounding box corners as Point3d objects.
  #
  # Returns Point3d array.
  def self.bb_corners(bb)

    (0..7).map { |c| bb.corner c }

  end

  # Calculate distance between point and plane.
  #
  # point        - The point.
  # plane        - The plane defined as an array of a point and vector.
  # use_negative - Whether negative length should be returned when point is
  #                behind plane (default: true).
  #
  # Returns Length.
  def self.distance_to_plane(point, plane, use_negative = true)

    point_on_plane = point.project_to_plane plane
    vector         = point - point_on_plane
    distance       = vector.length

    if distance != 0 && use_negative && !vector.samedirection?(plane[1])
      distance *= -1
    end

    distance

  end

  # Flatten vector to plane.
  #
  # v      - Vector.
  # normal - Normal to flatten along.
  #
  # Returns vector.
  def self.flatten_vector(v, normal = Z_AXIS)

    normal * v * normal

  end

  # Check if a point is in front of or behind a plane.
  # Direction is determined by plane normal vector.
  #
  # plane - Plane as array of a Point3d object and Vector3d object.
  # point - Point3d object to test.
  #
  # Returns true when in front of plane, false when behind.
  def self.front_of_plane?(plane, point)

    return if point.on_plane? plane
    (point.project_to_line(plane) - plane[0]).samedirection? plane[1]

  end

  # Creates a Transformation defined by an origin and three axes.
  # Unlike native Transformation.axes this also allows optional scaling and
  # skewing to be enabled.
  #
  # origin         - The origin as Point3d.
  # xaxis          - The X axis as Vector3d.
  # yaxis          - The X axis as Vector3d.
  # zaxis          - The X axis as Vector3d.
  # enable_scaling - Use lengths of axes for scale (default: false).
  # enable_skewing - Do not force axes to be perpendicular (default: false).
  #
  # Returns a Transformation.
  def self.transformation_axes(origin, xaxis, yaxis, zaxis, enable_scaling = false, enable_skewing = false)

    if xaxis.parallel?(yaxis) || yaxis.parallel?(zaxis) || zaxis.parallel?(xaxis)
      raise ArgumentError, "Axes must not be parallel."
    end

    # Create new Vectors instead of manipulating existing.
    xaxis = xaxis.clone
    yaxis = yaxis.clone
    zaxis = zaxis.clone

    # Mimic behavior of native Transformation.axes when skewing is disabled.
    # Behavior found through trial and error.
    unless enable_skewing
      if (xaxis*yaxis) % zaxis > 0
        # Right handed coordinate system.
        yaxis = zaxis*xaxis
        xaxis = yaxis*zaxis
      else
        # Left handed coordinate system.
        xaxis = zaxis*yaxis
        yaxis = xaxis*zaxis
      end
    end

    unless enable_scaling
      xaxis.normalize!
      yaxis.normalize!
      zaxis.normalize!
    end

    Geom::Transformation.new([
      xaxis.x,  xaxis.y,  xaxis.z,  0,
      yaxis.x,  yaxis.y,  yaxis.z,  0,
      zaxis.x,  zaxis.y,  zaxis.z,  0,
      origin.x, origin.y, origin.z, 1,
    ])

  end

  # Check if a Transformation is mirrored.
  def self.transformation_mirrored?(transformation)

    (transformation.xaxis*transformation.yaxis) % transformation.zaxis < 0

  end

end

end
