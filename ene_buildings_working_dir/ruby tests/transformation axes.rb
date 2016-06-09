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
def transformation_axes(origin, xaxis, yaxis, zaxis, enable_scaling = false, enable_skewing = false)

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
    if (xaxis*yaxis).angle_between(zaxis) < 90.degrees
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
