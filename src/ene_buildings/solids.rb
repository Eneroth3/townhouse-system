# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

# Public: Various solid operations.
#
# To use these operators in your own project, copy the whole class into it
# and into your own namespace (module).
#
# Differences from native solid tools:
#  *Preserves original group/component with its material, layer, attributes etc.
#  *Preserves raw geometry inside groups/components with its layer, attributes etc.
#  *Ignores nested geometry, a house is for instance still a solid you can cut away a part of even if there's a cut-opening window component in the wall.
#  *Operations on components alters all instances as expected.
#  *Doesn't break material inheritance. If a group/component itself is painted faces wont be painted in its material.
#  *Doesn't include tools I've never found a use for (this is a highly personal experience, I might add more if people want it) and has clearer icons.
#
# Face orientation is used on touching solids to determine whether faces should be removed or not.
# Make sure faces are correctly oriented when using.
class Solids

  # Public: Check if a group or component is solid. If every edge binds two faces
  # group/component counts as solid. Nested groups and components are ignored.
  #
  # group_or_component - The group or component to test.
  #
  # Returns true if solid, false if not and nil if not a group or component.
  def self.is_solid?(group_or_component)

    return unless [Sketchup::Group, Sketchup::ComponentInstance].any? { |c| group_or_component.is_a? c}
    ents = entities_from_group_or_componet group_or_component

    !ents.any? { |e| e.is_a?(Sketchup::Edge) && e.faces.length%2==1 }#odd?

  end

  # Public: Check whether point is inside, outside or on face of solid.
  #
  # point                     - Point to test (global coordinates).
  # group_or_component        - Group or component to test.
  # return_value_when_on_face - What to return when point is on face of solid.
  #                             (default: true)
  # verify_solid              - First check if group or components actually is
  #                             a solid. (default true)
  #
  # Returns true if point is inside group, false if outside and
  #   return_value_when_on_face when point is on face.
  #   Returns nil if group_or_component isn't a solid.
  #   Returns nil if group or component isn't a solid and verify_solid is true.
  def self.inside_solid?(point, group_or_component, return_value_when_on_face = true, verify_solid = true)

    return if verify_solid && !is_solid?(group_or_component)

    #Cast a ray from point in random direction an check how many times it intersects the mesh.
    #Odd number means it's inside mesh, even means it's outside of it.

    #Transform point to local coordinates of this group/component.
    #These coordinates are used in the API no matter current drawing context,
    #EXCEPT when the drawing context is inside this group/component.
    #This oddity seems to be undocumented but as long as the user isn't inside
    #this group/component everything should be just fine (I hope).
    #More info: http://forums.sketchup.com/t/what-is-coordinates-relative-to/3102
    point = point.clone
    point.transform! group_or_component.transformation.inverse

    #Use somewhat random vector to reduce risk of ray touching solid without
    #penetrating it.
    vector = Geom::Vector3d.new 234, 1343, 345
    line = [point, vector]
    intersections = []

    ents = entities_from_group_or_componet group_or_component
    ents.each do |f|
      next unless f.is_a?(Sketchup::Face)
      plane = f.plane

      #If point is on face of solid, return given value.
      clasify_point = f.classify_point point
      return return_value_when_on_face if [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include? clasify_point

      #Don't count face if ray tangents it.
      next if point.on_plane?(f.plane) && point.offset(vector).on_plane?(f.plane)

      intersection = Geom.intersect_line_plane line, plane
      next unless intersection
      next if intersection == point

      #Check if intersection is in the direction ray is casted.
      next unless (intersection - point).samedirection? vector

      #Check intersection's relation to face.
      #Counts as intersection if on face, including where cut-opening component cuts it.
      classify_intersection = f.classify_point intersection
      next unless [Sketchup::Face::PointInside, Sketchup::Face::PointOnEdge, Sketchup::Face::PointOnVertex].include? classify_intersection

      #Remember intersection so intersections can be counted.
      #Save intersection as array so duplicated intersections fro where ray meets edge between faces can be removed and counted as one.
      intersections << intersection.to_a
    end

    #If ray hits an edge 2 faces have intersections for the same point.
    #Only counts as hitting the mesh once though.
    #Duplicated point could both mean ray enters/leaves solid through an edge, but also that ray tangents an edge of the solid.
    #Use a quite random ray direction to heavily decrease the risk of ray touch solid.
    intersections.uniq!

    #Return
    intersections.length%2==1#odd?

  end

  # Public: Unite one solid group/component to another.
  #
  # The original group/component keeps its material, layer, attributes etc.
  # Raw geometry inside both groups/components keep their material layer
  # attributes etc.
  #
  # original         - The original group/component.
  # to_add           - The group/component to add to the original.
  # wrap_in_operator - True to add an operation so all changes can be undone in
  #                    one step. Set to false when called from custom script
  #                    that already uses an operator. (default: true)
  #
  # Returns true if result is a solid, false if something went wrong.
  def self.union(original, to_add, wrap_in_operator = true)

    #Check if both groups/components are solid.
    return if !is_solid?(original) || !is_solid?(to_add)

    original.model.start_operation "Union", true if wrap_in_operator

    #Make groups unique so no other instances of are altered.
    #Group.make_unique is for some reason deprecated, change name instead.
    original.name += "" if original.is_a? Sketchup::Group

    #Create new group for to_add so components sharing same definition
    #aren't affected.
    temp_group = original.parent.entities.add_group
    move_into temp_group, to_add
    to_add = temp_group

    original_ents = entities_from_group_or_componet original
    to_add_ents = entities_from_group_or_componet to_add

    old_coplanar = find_coplanar_edges original_ents
    old_coplanar += find_coplanar_edges to_add_ents

    #Double intersect so intersection edges appear in both contexts.
    intersect original, to_add

    #Remove faces that are inside the solid of the other group.
    #Also remove faces that exists in both groups and have opposite orientation.
    to_remove = find_faces original, to_add, true, false
    to_remove1 = find_faces to_add, original, true, false
    corresponding = find_corresponding_faces original, to_add, false
    corresponding.each_with_index { |v, i| i%2==0 ? to_remove << v : to_remove1 << v }#even?
    original_ents.erase_entities to_remove
    to_add_ents.erase_entities to_remove1

    #Move to_add into original_ents and explode it.
    move_into original, to_add

    #Purge edges no longer not binding 2 edges.
    purge_edges original_ents

    #Remove co-planar edges that occurred from the intersection (not those that already existed)
    all_coplanar = find_coplanar_edges original_ents
    new_coplanar = all_coplanar - old_coplanar
    original_ents.erase_entities new_coplanar

    original.model.commit_operation if wrap_in_operator

    #Return whether result is solid or not
    is_solid? original

  end

  # Public: Subtract one solid group/component from another.
  #
  # The original group/component keeps its material, layer, attributes etc.
  # Raw geometry inside both groups/components keep their material layer
  # attributes etc.
  #
  # original         - The original group/component.
  # to_subtract      - The group/component to subtract from the original.
  # wrap_in_operator - True to add an operation so all changes can be undone in
  #                    one step. Set to false when called from custom script
  #                    that already uses an operator. (default: true)
  # keep_to_subtract - Prevent deletion of solid to subtract. This turns method
  #                    Into a trim method, however the separate method is
  #                    recommended for more readable code. (default: false)
  #
  # Returns true if result is a solid, false if something went wrong.
  def self.subtract(original, to_subtract, wrap_in_operator = true, keep_to_subtract = false)

    #Check if both groups/components are solid.
    return if !is_solid?(original) || !is_solid?(to_subtract)

    op_name = keep_to_subtract ? "Trim" : "Subtract"
    original.model.start_operation op_name, true if wrap_in_operator

    #Make groups unique so no other instances of are altered.
    #Group.make_unique is for some reason deprecated, change name instead.
    original.name += "" if original.is_a? Sketchup::Group

    #Create new group for to_subtract so components sharing same definition
    #aren't affected.
    temp_group = original.parent.entities.add_group
    move_into temp_group, to_subtract, keep_to_subtract
    to_subtract = temp_group

    original_ents = entities_from_group_or_componet original
    to_subtract_ents = entities_from_group_or_componet to_subtract

    old_coplanar = find_coplanar_edges original_ents
    old_coplanar += find_coplanar_edges to_subtract_ents

    #Double intersect so intersection edges appear in both contexts.
    intersect original, to_subtract

    #Remove edges in original that are inside to_subtract and
    #edges in to_subtract that are outside original.
    to_remove = find_faces original, to_subtract, true, false
    to_remove1 = find_faces to_subtract, original, false, false
    corresponding = find_corresponding_faces original, to_subtract, true
    corresponding.each_with_index { |v, i| i%2==0 ? to_remove << v : to_remove1 << v }#even?
    original_ents.erase_entities to_remove
    to_subtract_ents.erase_entities to_remove1

    #Reverse all faces in to_subtract
    to_subtract_ents.each { |f| f.reverse! if f.is_a? Sketchup::Face }

    #Move to_subtract into original_ents and explode it.
    move_into original, to_subtract

    #Remove co-planar edges that occurred from the intersection (not those that
    #already existed)
    all_coplanar = find_coplanar_edges original_ents
    new_coplanar = all_coplanar - old_coplanar
    original_ents.erase_entities new_coplanar

    #Purge edges no longer binding 2 faces.
    #Faces that where in the same plane in the different solids may have been
    #kept even if they are outside the expected resulting solid.
    #Remove all edges not binding 2 faces to get rid of them.
    purge_edges original_ents

    original.model.commit_operation if wrap_in_operator

    #Return whether result is solid or not
    is_solid? original

  end

  # Public: Trim one solid group/component from another.
  #
  # The original group/component keeps its material, layer, attributes etc.
  # Raw geometry inside both groups/components keep their material layer
  # attributes etc.
  #
  # original         - The original group/component.
  # to_trim          - The group/component to trim away from the original.
  # wrap_in_operator - True to add an operation so all changes can be undone in
  #                    one step. Set to false when called from custom script
  #                    that already uses an operator.
  #
  # Returns true if result is a solid, false if something went wrong.
  def self.trim(original, to_trim, wrap_in_operator = true)

    #Call subtract method with keep_to_subtract set to true.
    subtract(original, to_trim, wrap_in_operator, true)

  end

  #Following methods are used internally and may be subject to change between
  #releases. Typically names may change.

  # Internal: Get the Entities object for either a Group or CompnentInstance.
  #
  # group_or_component - The group or ComponentInstance object.
  #
  # Returns an Entities object.
  def self.entities_from_group_or_componet(group_or_component)

    #This method is called very often in script but is so fast it shouldn't be
    #a problem.
    return group_or_component.entities if group_or_component.is_a?(Sketchup::Group)
    group_or_component.definition.entities

  end

  # Internal: Intersect solids and get intersection edges in both solids.
  #
  # ent0 - One of the groups or components to intersect.
  # ent1 - The other groups or components to intersect.
  #
  #Returns nothing.
  def self.intersect(ent0, ent1)

    ents0 = entities_from_group_or_componet ent0
    ents1 = entities_from_group_or_componet ent1

    #Intersect twice to get coplanar faces.
    #Copy the intersection geometry to both solids.
    #Both solids must be in the same drawing context which they are moved to
    #in union and subtract method.
    temp_group = ent0.parent.entities.add_group

    #ents0.intersect_with false, ent0.transformation, temp_group.entities, temp_group.transformation, true, ent1
    #ents1.intersect_with false, ent1.transformation, temp_group.entities, temp_group.transformation, true, ent0

    #Only intersect raw geometry, save time and avoid unwanted edges.
    ents0.intersect_with false, ent0.transformation, temp_group.entities, temp_group.transformation, true, ents1.to_a.select { |e| [Sketchup::Face, Sketchup::Edge].include?(e.class) }
    ents1.intersect_with false, ent1.transformation, temp_group.entities, temp_group.transformation, true, ents0.to_a.select { |e| [Sketchup::Face, Sketchup::Edge].include?(e.class) }

    move_into ent0, temp_group, true
    move_into ent1, temp_group

    nil

  end

  # Internal: Return a point that is somewhere inside a face, not on its edge or
  # corner.
  #
  # face - The face to find a point in.
  #
  # Returns a Point3d object.
  def self.point_in_face(face)

    face.vertices.each_with_index do |v, i|
      p_this = v.position
      p_before = face.vertices[i-1].position#Use third points to allow for triangles.
      p_2nd_before = face.vertices[i-2].position
      p = Geom.linear_combination 0.5, p_this, 0.5, p_2nd_before
      p = Geom.linear_combination 0.5, p, 0.5, p_before
      return p if face.classify_point(p) == Sketchup::Face::PointInside
    end

    false#Should never reach this line. IF false is returned algorithm is wrong.

  end

  # Internal: Find faces to remove based on their position relative to the
  # other solid.
  def self.find_faces(to_search_in, reference, inside, on_surface)

    to_remove_in_ents = entities_from_group_or_componet to_search_in

    to_remove_in_ents.select do |f|
      next unless f.is_a? Sketchup::Face
      point = point_in_face f
      point.transform! to_search_in.transformation
      #Do not verify if solid actually is solid each iteration.
      #It may not be a solid any longer if loose edges were created from nested
      #groups or components during intersection.
      next if inside != inside_solid?(point, reference, inside == on_surface, false)
      true
    end

  end

  # Internal: Find faces that exists with same location in both contexts.
  #
  # same_orientation - true to only return those oriented the same direction,
  #                    false to only return those oriented the opposite
  #                    direction and nil to skip direction check.
  #
  # Returns an array of faces, every second being in each drawing context.
  def self.find_corresponding_faces(ent0, ent1, same_orientation)

    ents0 = entities_from_group_or_componet ent0
    ents1 = entities_from_group_or_componet ent1

    faces = []

    ents0.each do |f0|
      next unless f0.is_a? Sketchup::Face
      normal0 = f0.normal.transform ent0.transformation
      points0 = f0.vertices.map { |v| v.position.transform ent0.transformation }
      ents1.each do |f1|
        next unless f1.is_a? Sketchup::Face
        normal1 = f1.normal.transform ent1.transformation
        next unless normal0.parallel? normal1
        points1 = f1.vertices.map { |v| v.position.transform ent1.transformation }
        next unless points0.all? { |v| points1.include?(v) }
        unless same_orientation.nil?
          next if normal0.samedirection?(normal1) != same_orientation#NOTE: FEATURE: this check is based on face orientation. Faces might be faulty oriented.
        end
        faces << f0
        faces << f1
      end
    end

    faces


  end#def

  # Internal: Remove all loose edges binding less than 2 edges.
  def self.purge_edges(ents)

    ents.erase_entities ents.select { |e|
      next unless e.is_a? Sketchup::Edge
      next unless e.faces.length < 2
      true
    }

  end

  # Internal: Merges groups/components.
  # Requires both groups/components to be in the same drawing context.
  def self.move_into(destination, to_move, keep = false)#NOTE: FEATRUE: makes transformations in this method work when not in same drawing context and whole class will work when solids are in different contexts. check if native solids can do this, if not document it as one of the differences!

    #Create a new instance of the group/component.
    #Properties like material and attributes will be lost but should not be used
    #anyway because group/component is exploded.
    #References to entities will be kept. Hooray!

    destination_ents = entities_from_group_or_componet destination

    to_move_def = to_move.is_a?(Sketchup::Group) ? to_move.entities.parent : to_move.definition

    trans_target = destination.transformation
    trans_old = to_move.transformation

    trans = trans_old*(trans_target.inverse)
    trans = trans_target.inverse*trans*trans_target#Transform transformation so it's relative to local and not global axes.

    temp = destination_ents.add_instance to_move_def, trans
    to_move.erase! unless keep
    temp.explode

  end

  # Internal: Find all co-planar edges in entities with both faces having same
  # material and layer.
  def self.find_coplanar_edges(ents)

    ents.select do |e|
      next unless e.is_a? Sketchup::Edge#Next returns nil which evaluates to false, exuding this entity.
      next unless e.faces.length == 2
      f0 = e.faces[0]
      f1 = e.faces[1]

      #next unless f0.material == f1.material#Prevented subtract from functioning as intended.
      #next unless f0.layer == f1.layer

      verts = f0.vertices
      !verts.any? { |v| f1.classify_point(v.position) == Sketchup::Face::PointNotOnPlane}
    end

  end

end

end
