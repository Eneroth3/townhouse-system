=begin
point  = Geom::Point3d.new  0, 0, 0
x_axis = Geom::Vector3d.new 1, 0, 0
y_axis = Geom::Vector3d.new 0, 1, 0
z_axis = Geom::Vector3d.new 0, 0, 1
=end

def transformation_axes(point, x_axis, y_axis, z_axis, enable_scaling = false, enable_skewing = true)

  if x_axis.parallel?(y_axis) || y_axis.parallel?(z_axis) || z_axis.parallel?(x_axis)
    raise ArgumentError "Axes must not be parallel."
  end
  
  # Create new object instead of manipulating existing.
  x_axis = x_axis.clone
  y_axis = y_axis.clone
  z_axis = z_axis.clone

  # Mimic behavior of native Transformation.axes when skewing is disabled.
  unless enable_skewing
    # Keep X, Move Y in the plane Y and X forms, let Z do whatever happens to it.
    #z_axis = x_axis*y_axis
    #y_axis = z_axis*x_axis
    
    # Keep Z, Move X in the plane Z and X forms, let Y do whatever happens to it.
    y_axis = z_axis*x_axis
    x_axis = y_axis*z_axis
  end
    
  unless enable_scaling
    x_axis.normalize!
    y_axis.normalize!
    z_axis.normalize!
  end
  
  Geom::Transformation.new([
    x_axis.x, x_axis.y, x_axis.z, 0,
    y_axis.x, y_axis.y, y_axis.z, 0,
    z_axis.x, z_axis.y, z_axis.z, 0,
    point.x,  point.y,  point.z,  1,
  ])

end