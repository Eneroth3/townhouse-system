# To test, create a new model containing one group or component only.
# Run this:
#   Sketchup.active_model.entities.first.transformation = transformation_axes(point, x_axis, y_axis, z_axis, false, true)

# TODO: Behaves different from native method for negative values in coordinates when skewing. 

def transformation_axes(point, x_axis, y_axis, z_axis, enable_scaling = false, enable_skewing = false)

  if x_axis.parallel?(y_axis) || y_axis.parallel?(z_axis) || z_axis.parallel?(x_axis)
    raise ArgumentError, "Axes must not be parallel."
  end
  
  # Create new Vectors instead of manipulating existing.
  x_axis = x_axis.clone
  y_axis = y_axis.clone
  z_axis = z_axis.clone

  # Mimic behavior of native Transformation.axes when skewing is disabled.
  unless enable_skewing
    ###un_adjusted_y = y_axis
    y_axis = z_axis*x_axis
    x_axis = y_axis*z_axis
    ###y_axis.reverse! if y_axis.angle_between(un_adjusted_y) > 180.degrees
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









# Test

# Is this what a unit test is?

def random_vector
  
  Geom::Vector3d.new(rand(-1.0..1.0), rand(-1.0..1.0), rand(-1.0..1.0))
  
end

def same_trasnformation(t0, t1)
  
  a0 = t0.to_a
  a1 = t1.to_a
  
  i = 0
  a0.all? do |_|
    v0 = a0[i]
    v1 = a1[i]
    i += 1
p v0
p v1
    v0.to_l == v1.to_l
  end
  
end

def test

  ents = Sketchup.active_model.entities

  (1..10).each do |i|
  
    p = Geom::Point3d.new i.m*4, 0, 0
    
    x = random_vector
    y = random_vector
    z = random_vector
    my_transform = transformation_axes p, x, y, z
    su_transform = Geom::Transformation.axes p, x, y, z
    
    puts "right-handed system: #{(x*y).angle_between(z) < 90.degrees}"
    
    #puts "Same transformation: #{same_trasnformation(my_transform, su_transform)}"
        
    g = ents.add_group
    g.transformation = my_transform
    f = g.entities.add_face(ORIGIN, [1.m, 0, 0], [1.m, 1.m, 0], [0, 1.m, 0])
    f.pushpull -1.m
    
    
    g = ents.add_group
    g.transformation = su_transform
    f = g.entities.add_face(ORIGIN, [1.m, 0, 0], [1.m, 1.m, 0], [0, 1.m, 0])
    f.pushpull -1.m
    g.material = "Red"
    
    
    ents.add_line p, p.offset(x, 2.m)
    ents.add_line p, p.offset(y, 2.m)
    ents.add_line p, p.offset(z, 2.m)
    
    
    
    
  end

end
