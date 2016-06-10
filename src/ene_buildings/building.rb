# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

# Public: A Building object consists of a reference to a Template, a path
# (Point3d Array, horizontal) and a reference to a Group its drawn to.
# Additionally it has some information how to read the Template, for instance if
# any materials should be replaced.
#
# Building objects are created when they are needed, for instance when the
# properties dialog is opened or when the reposition tool is used on it.
# All the Building data is stored to the Group.
class Building

  # Public: Name of attribute dictionary for data in Building Group.
  # Uses term "house" instead of "building" for backward compatibility.
  ATTR_DICT = "#{ID}_house"

  # Internal: Warning message when entering building group
  # Used in observer.
  ENTER_WARNING =
    "You are about to enter a building drawn by #{NAME}.\n"\
    "Manually made changes will be lost when redrawn by plugin.\n\n"\
    "Do you want to continue?"

  # Internal: Statusbar text.
  STATUS_DRAWING       = "Drawing Building..."
  STATUS_DONE          = "Done Drawing."
  STATUS_SOLIDS        = "Performing solid operations"
  STATUS_CUTTING       = "Cutting opening"
  STATUS_CUT_INTERSECT = "Intersecting..."

  # Class methods

  # Public: Get the Building object for the selected building group.
  # Used in menus for instance.
  #
  # Returns a Building object or nil if not a single group that is a building is
  # selected.
  def self.get_from_selection

    selection  = Sketchup.active_model.selection
    return unless selection.size == 1
    e = selection.first
    return unless e.attribute_dictionary ATTR_DICT

    new e

  end

  # Public: Check if an object is a Group a Building is drawn to.
  # Performs fast check without initializing Building object from Group.
  #
  # entity - The object to test.
  #
  # Returns true if is a Building Group, otherwise false.
  def self.group_is_building?(entity)

    return false unless entity.is_a?(Sketchup::Group)
    return false unless entity.attribute_dictionary ATTR_DICT

    true

  end
  
  # Public: Check if selection is a Group a Building is drawn to.
  # Performs fast check without initializing Building object from group.
  #
  # Returns true if is a Building Group, otherwise false.
  def self.selection_is_building?

    selection  = Sketchup.active_model.selection
    return unless selection.size == 1

    group_is_building? selection.first

  end

  # Internal: Display message telling user they are entering a Building Group.
  # Called from observer.
  #
  # Returns true if user wants to proceed, false if user wants to cancel.
  def self.onGroupEnter
  
    UI.messagebox(ENTER_WARNING, MB_OKCANCEL) == IDOK
    
  end
  
  # Instance attribute accessors
  
  # Public: Gets/sets whether path represents building back side instead of
  # front.
  attr_accessor :back_along_path
  
  # Public: Gets/sets component replacements.
  # Array where each element is array of original (string identifier) and
  # replacement (array of replacement of each slot, also string identifier).
  attr_accessor :componet_replacement

  # Public: Gets/sets rotation of gables.
  # Array containing 2 angels in radians cc seen from above.
  attr_accessor :end_angles

  # Public: Returns Group Building is drawn to.
  attr_reader :group

  # Public: Gets/set material replacements.
  # Array where each element is an array of original and replacement Material.
  attr_accessor :material_replacement

  # Public: Gets/sets path Building is drawn to in local coordinates of the
  # parent  drawing context (e.g. model root or a group representing a
  # property). When group is manually moved in SU the path will be transformed
  # along with it and be updated next time an object is loaded from it.
  # Make sure all points have same z value.
  attr_accessor :path

  # Public: Gets/set whether solid operations should e performed, boolean.
  attr_accessor :perform_solid_operations

  # Public: Gets/sets Template object for Building.
  attr_accessor :template

  # Instance methods

  # Public: Create a new Building object.
  #
  # group - Group to base Building on. Used to re-create previously created
  #         object (default: nil).
  def initialize(group = nil)

    # Make sure templates are loaded.
    Template.require_all

    if group

      # Load saved object attributes from group.
      @group = group
      load_attributes

    else

      # Initialize variables.

      # Reference to template object.
      @template

      # Point3d Array of where to draw building.
      @path = []
      
      @back_along_path = false

      # End angles in radians.
      @end_angles = [0, 0]

      # Array of Materials to replace and replacement.
      # Each element is an array containing the original and the replacement
      # Material object.
      @material_replacement = []

      # Array... TODO: COMPONENT REPLACEMENT.
      @componet_replacement = []

      # Boolean telling whether solid operations should be performed during
      # building drawing.
      @perform_solid_operations = true

    end

  end

  # Public: Draws building.
  # Shortcut for all the drawing methods.
  #
  # entities     - Entities object (drawing context) to add building group to if
  #                not yet drawn (default: current).
  # exlude_basic - When true the basic drawing method is skipped and only
  #                methods customizing the basic building are run. (default: false)
  #
  #                Typically the basic drawing (just applying template to path)
  #                is done first, then data is acquired from the building to see
  #                what can be customized (materials, components etc) and
  #                Then all other draw methods are called to customize the
  #                the basic building based on acquired data.
  # write_status - Write to statusbar while drawing (default: true).
  #
  # Returns nothing.
  def draw(entities = nil, exlude_basic = false, write_status = true)
  
    raise "No template set for building." unless @template

    Sketchup.status_text = STATUS_DRAWING if write_status

    draw_basic(entities) unless exlude_basic
    ### draw_replace_components
    ### draw_corners
    ### draw_gabels
    draw_solids write_status
    draw_replace_materials
    save_attributes

    Sketchup.status_text = STATUS_DONE if write_status

  end

  # Public: Performs the basic Building drawing.
  #
  # This method draws building template to path but does not customize building.
  # Other methods are called to replace materials and groups/components
  # according to building properties.
  #
  # entities     - Entities object (drawing context) to add Building Group to if
  #                not yet drawn (default: current).
  #
  # Returns nothing.
  def draw_basic(entities = nil)

    entities ||= Sketchup.active_model.active_entities

    # Create group if there isn't one.
    if !@group || @group.deleted?
      @group = entities.add_group
    end

    # Prepare for drawing.
    ents = @group.entities
    ents.clear!

    # Transform path to local building coordinates.
    trans_inverse = @group.transformation.inverse
    path = @path.map { |p| p.transform trans_inverse }

    # Get tangent for each point in path.
    # Tangents point in the positive direction of path.
    tangents = []
    tangents << path[1] - path[0]
    if path.size > 2
      (1..path.size - 2).each do |corner|
        p_prev = path[corner - 1]
        p_here = path[corner]
        p_next = path[corner + 1]
        v_prev = p_here - p_prev
        v_next = p_next - p_here
        tangents << Geom.linear_combination(0.5, v_prev, 0.5, v_next)
      end
    end
    tangents << path[-1] - path[-2]

    # Rotate first and last tangent according to @end_angles.
    tangents.first.transform! Geom::Transformation.rotation ORIGIN, Z_AXIS, @end_angles.first
    tangents.last.transform! Geom::Transformation.rotation ORIGIN, Z_AXIS, @end_angles.last
    
    # If building should be drawn with it back along the path instead of its
    # front, reverse the path and tangents.
    # The terms left and right relates to the building front side.
    if @back_along_path
      path.reverse!
      tangents.reverse!
      tangents.each { |t| t.reverse! }
    end
    
    # Main Volume(s).
    # Volume is placed and fitted to each segment in path.
    (0..path.size - 2).each do |segment_index|

      # Some variables in building coordinates.
      corner_l = path[segment_index]
      corner_r = path[segment_index + 1]
      s_vector = corner_r - corner_l
      s_width = s_vector.length
      tangent_l = tangents[segment_index]
      tangent_r = tangents[segment_index + 1]

      # Place building component (as group) with origin on left corner and X axis
      # pointing towards right one (seen from front).
      # building side following path (usually front) lies on Y axis.
      segment_trans  = Geom::Transformation.axes corner_l, s_vector, Z_AXIS * s_vector, Z_AXIS
      segment_group  = ents.add_group
      segment_group.transformation = segment_trans
      segment_ents   = segment_group.entities
      component_trans = if @back_along_path
        Geom::Transformation.new [0, -(@template.depth || Template::FALLBACK_DEPTH), 0]
      else
        Geom::Transformation.new
      end
      component_inst = segment_ents.add_instance @template.component_def, component_trans
      component_inst.explode
      segment_ents_raw = segment_ents.select { |e| [Sketchup::Edge, Sketchup::Face].include? e.class }
                  
      # Allow material replacement in segment group.
      segment_group.set_attribute Template::ATTR_DICT_PART, "replace_nested_mateials", true

      # Segment end planes, local segment coordinates.
      plane_l = [ORIGIN, tangent_l.reverse.transform(segment_trans.inverse)]
      plane_r = [[s_width, 0, 0], tangent_r.transform(segment_trans.inverse)]

      # Left and right wall faces.
      faces_l = segment_ents.select { |e| e.is_a?(Sketchup::Face) && e.normal.samedirection?([-1,0,0]) }
      faces_r = segment_ents.select { |e| e.is_a?(Sketchup::Face) && e.normal.samedirection?([1,0,0]) }
      unless faces_l.size == 1 && faces_r.size == 1# TODO: Make separate validation method.
        msg =
          "Invalid building volume. Template root must contain exactly 2 "\
          "gable faces, one with its normal along positive X and one with its "\
          "normal along negative X."
        raise msg
      end
      face_l = faces_l.first
      face_r = faces_r.first

      # Hide walls between segments.
      unless segment_index == 0
        face_l.hidden = true
        face_l.edges.each { |e| e.hidden = true if e.line[1].perpendicular?(Z_AXIS) }
      end
      unless segment_index == path.size - 2
        face_r.hidden = true
        face_r.edges.each { |e| e.hidden = true if e.line[1].perpendicular?(Z_AXIS) }
      end

      # Remove replacement component/groups, corners, gables etc from this group.
      # (corners and gables are added later and are not a part of each segment.)
      # TODO: COMPONENT REPLACEMENT: Remove these entities.

      # Adapt building volume to fill this segment.
      # The building template model can have any width.
      # Side walls are moved and sheared to fit.
      x_l = face_l.vertices.first.position.x
      x_r = face_r.vertices.first.position.x
      ents_l = segment_ents_raw.select { |e| e.vertices.all? { |v| v.position.x.to_l == x_l } }
      ents_r = segment_ents_raw.select { |e| e.vertices.all? { |v| v.position.x.to_l == x_r } }
      
      trans_a = Geom::Transformation.new.to_a

      trans_a_l = trans_a.dup
      trans_a_l[12] = -x_l
      trans_a_l[4] = -plane_l[1].y/plane_l[1].x# Y value of tangent in local coordinates is same as x for (horizontal) normal.
      trans_l = Geom::Transformation.new trans_a_l

      trans_a_r = trans_a.dup
      trans_a_r[12] = -x_r + s_width
      trans_a_r[4] = -plane_r[1].y/plane_r[1].x
      trans_r = Geom::Transformation.new trans_a_r

      segment_ents.transform_entities trans_l, ents_l
      segment_ents.transform_entities trans_r, ents_r

      # Copy and position nested groups/components (parts).
      # z and y position is kept, x is calculated from a formula in attributes.
      segment_ents.to_a.each do |e|
        next unless [Sketchup::Group, Sketchup::ComponentInstance].include? e.class
        next unless ad = e.attribute_dictionary(Template::ATTR_DICT_PART)

        origin = e.transformation.origin
        line = [origin, Geom::Vector3d.new(1, 0, 0)]
        point_l = Geom.intersect_line_plane line, plane_l
        point_r = Geom.intersect_line_plane line, plane_r
        trans_a = e.transformation.to_a

        if ad["align"]
          # Align one group/component.
          # Either "left", "right", "center" or percentage (float between 0 and
          # 1).
          new_origin =
            if ad["align"] == "left"
              point_l
            elsif ad["align"] == "right"
             point_r
            elsif ad["align"] == "center"
              Geom.linear_combination 0.5, point_l, 0.5, point_r
            elsif ad["align"].is_a? Float
              Geom.linear_combination(1-ad["align"], point_l, ad["align"], point_r)
            end
          trans_a[12] = new_origin.x
          e.transformation = Geom::Transformation.new trans_a

        elsif ad["spread"]
          # Spread multiple groups/components.
          # Either Fixnum telling number of copies or float/length telling
          # approximate distance between (in inches). This distance will adapt
          # to available space.
          available_distance = point_l.distance point_r
          margin_l = ad["margin_left"] || ad["margin"] || 0
          margin_r = ad["margin_right"] || ad["margin"] || 0
          available_distance -= (margin_l + margin_r)
          if ad["spread"].is_a?(Fixnum)
            total_number = ad["spread"]
            raise "If 'spread' is a Fuxnum it must be zero or more." if total_number < 0
          else
            total_number = available_distance/ad["spread"]
            raise "If 'spread' is a Length it must bigger than zero." unless ad["spread"] > 0
            # Round total_number to closets Int or force to odd/even.
            #(If rounding is set to anything else than "force_odd" it's used as "force_even".)
            total_number =
              if ad["rounding"]
                fraction = total_number%2
                (ad["rounding"] == "force_odd") && fraction > 1 ? total_number.floor : total_number.ceil
              else
                total_number.round
              end
          end
          distance_between = available_distance/total_number
          # Each copy has its origin at x = margin_l + (n + 0.5)*distance_between
          e_def = e.definition
          transformations = (0..total_number-1).map do |n|
            x = point_l.x + margin_l + (n + 0.5) * distance_between
            trans_a[12] = x
            trans = Geom::Transformation.new trans_a
            # Don't place anything with its bounding box outside the segment if
            # not specifically told to do so.
            unless ad["override_cut_planes"]
              corners = MyGeom.bb_corners(e_def.bounds)
              corners.each { |c| c.transform! trans }
              next if corners.any? { |c| MyGeom.front_of_plane?(plane_l, c) || MyGeom.front_of_plane?(plane_r, c) }
            end
            trans
          end
          transformations.compact!
          if transformations.empty?
            # Remove existing component if it didn't fit.
            e.erase!
          else
            # Position existing group/component.
            e.transformation = transformations.first
            # Place new ones.
            (1..transformations.size - 1).each do |n|
              instance = segment_ents.add_instance e_def, transformations[n]
              instance.material = e.material
              instance.layer = e.layer
              instance.name = e.name
              instance.glued_to = e.glued_to if e.is_a?(Sketchup::ComponentInstance) && e.glued_to
              EneBuildings.copy_attributes e, instance
            end
          end
        end

      end
      
      # TODO: Component Replacement: replace here. Or possibly draw add the replacements from the start when the transformations are calculated before anything is even placed

      # Hack: glue all components to the face they are on.
      # Components may loose their glued face when adapting segment volume.
      # All references to faces saved before refers to deleted entities
      # after.
      segment_ents.to_a.each do |f|
        next unless f.is_a? Sketchup::Face
        segment_ents.to_a.each do |c|
          next unless c.respond_to? :glued_to
          next if c.glued_to
          t = c.transformation
          next unless f.normal.samedirection? t.zaxis
          next unless f.classify_point(t.origin) == Sketchup::Face::PointInside
          c.glued_to = f
        end
      end

    end# Main volume (each segment)

    # TODO: Place corner and gable parts here.
    
    nil

  end

  # Public: Replaces groups/components in Building Group according to
  # @componet_replacement.
  #
  # After this method was last run draw_basic must be called to
  # reset original components to replace.
  #
  # Returns nothing.
  def draw_replace_components

    #...copy all attributes from replacement, e.g. solid operations.

  end

  # Public: Replaces materials in Building Group according to
  # @material_replacement.
  #
  # After this method was last run draw_basic must be called to reset original
  # materials to replace.
  #
  # Returns nothing.
  def draw_replace_materials

    return if @material_replacement.empty?

    # Hash of replacements. Original as key and replacement as value.
    # Used for faster indexing.
    replace  = Hash[*@material_replacement.flatten]

    # Recursive material replacer.
    # Replace materials in group and in all nested groups with an attribute
    # specifically telling it to do so.
    recursive = lambda do |group|
      group.name += ""# Make group unique.
      group.entities.each do |e|
        next unless e.respond_to? :material
        replacment = replace[e.material]
        e.material = replacment if replacment

        if e.is_a?(Sketchup::Group) && e.get_attribute(Template::ATTR_DICT_PART, "replace_nested_mateials")# OPTIMIZE: edit groups using same definition once. Create one new definition for all instances in this building (this entities collection)
          recursive.call(e)
        end
      end
    end

    # Replace materials in all groups in building root (segments, corner etc).
    recursive.call @group

    nil

  end

  # Public: Perform solid operations on Building if @perform_solid_operations is
  # true.
  #
  # After this method was last run draw_basic must be called to reset original
  # building solids.
  #
  # write_status - Write to statusbar that solid operations are performed
  #                (default: true).
  #
  # Returns nothing.
  def draw_solids(write_status = true)

    return unless @perform_solid_operations
    
    segment_groups = @group.entities.select { |e| e.is_a? Sketchup::Group }
    #TODO: future version: only include segments, not hörntorn, gables etc.

    ops = []
    hidden = []

    # List all parts to perform operations with.
    # Parts are listed in all segments before any solid operation is performed
    # so statusbar can show the total number of operations when showing progress.
    segment_groups.each do |segment_group|

      # Find groups and components to perform solid operations with.
      segment_group.entities.to_a.each do |e|
        hidden << e if e.hidden?
        next unless [Sketchup::Group, Sketchup::ComponentInstance].include? e.class
        next unless ad = e.attribute_dictionary(Template::ATTR_DICT_PART)
        next unless operation = ad["solid"]
        ops << [e, operation, segment_group]
      end

      # Sort by solid_index.
      # Smallest number first, 0 as default.
      ops.sort_by! do |s|
        s[0].get_attribute(Template::ATTR_DICT_PART, "solid_index", 0)
      end

    end

    nbr_solid_ops = ops.count { |o| o[1] != "cut_multiple_faces" }
    nbr_cutting_ops = ops.size - nbr_solid_ops
    
    # Show all hidden entities to prevent Sketchup popup telling user shown and
    # hidden geometry was merged.
    hidden.each { |e| e.hidden = false }

    # Perform solid operations.
    ops.each_with_index do |s, i|
      part, operation, segment_group = s
	    next if operation == "cut_multiple_faces"

      progress = " (#{i + 1}/#{nbr_solid_ops})"
      Sketchup.status_text = STATUS_SOLIDS + progress if write_status

      # Only allow certain strings as solid operators to prevent code
      # injection from building template.
      next unless %w(union subtract).include? operation

      # "Lift" up to parent drawing context.
      trans = segment_group.transformation * part.transformation
      instance = @group.entities.add_instance part.definition, trans

      # Perform solid operation.
      Solids.send operation, segment_group, instance, false

      # Remove original group/component.
      part.erase!
    end

    # Re-hide geometry.
    # Entities may have been deleted during solid operations or just refer to
    # a small part of the original entity.
    hidden.each { |e| e.hidden = true unless e.deleted? }
	
    # REVIEW: Move multi face cut to external class. Make separate method for copying edges and possibly other geometry.
  
    # Perform own multiple-face cut-opening.
    # Done after solid operations since it's not strictly a solid operation.
    i = 0
    segment_groups.each do |segment_group|
    
      
      # Copy naked edges on cutting parts into parent drawing context and keep
      # reference to new edges.
      # Also keep references to the end points of each edge, in normalized
      # order, to later determine which faces are inside the cutting edges.
      cutting_edges = []
      cutting_edge_points = []
      ops.each do |s|
        part, operation, part_segment_group = s
        next unless part_segment_group == segment_group
        next unless operation == "cut_multiple_faces"
        
        progress = " (#{i + 1}/#{nbr_cutting_ops})"
        i += 1
        Sketchup.status_text = STATUS_CUTTING + progress if write_status
        
        naked_edges = EneBuildings.naked_edges part.definition.entities
        
        naked_edges.each do |edge|
          points = edge.vertices.map { |v| v.position }
          points.each { |p| p.transform! part.transformation }
          points.reverse! if edge.reversed_in?(edge.faces.first)
          cutting_edge_points << points
          
          new_edge = segment_group.entities.add_line points
          new_edge.hidden = edge.hidden?
          cutting_edges << new_edge
        end
        
      end
      
      # HACK: Run intersect to split edges where they cross and punch holes in
      # faces. Would be much much very much faster if the geometry merger
      # that runs after each tool operation in SU could be called directly.
      #
      # Also use attributes for referencing cutting edges since attributes
      # are kept on both sides when an edge is split.
      # Life would be easier if the internal geometry merger thing could be
      # called as somehow return the relationship between new entities
      # and the entities they are split off from.
      cutting_edges.each { |e| e.set_attribute ID, "cutting_edges", true }
      Sketchup.status_text = STATUS_CUT_INTERSECT if write_status
      cutting_edges += segment_group.entities.intersect_with(
        false,
        Geom::Transformation.new,
        segment_group.entities,
        Geom::Transformation.new,
        true,
        cutting_edges
      )
      cutting_edges.keep_if { |e| e.valid? }
      cutting_edges += segment_group.entities.select { |e| e.get_attribute ID, "cutting_edges" }
      cutting_edges.uniq!
      
      # MUCH HACK: Do the freaking thing again if some of the cutting edges are
      # still free standing. When some cutting objects touches the outer loops
      # of a face somehow the the intersect method fucks up with finding inside
      # loops for that face.
      free_cutting_edges = cutting_edges.select { |e| e.faces.empty? }
      unless free_cutting_edges.empty?
        cutting_edges += segment_group.entities.intersect_with(
          false,
          Geom::Transformation.new,
          segment_group.entities,
          Geom::Transformation.new,
          true,
          free_cutting_edges
        )
        cutting_edges.keep_if { |e| e.valid? }
        cutting_edges += segment_group.entities.select { |e| e.get_attribute ID, "cutting_edges" }
        cutting_edges.uniq!
      end
     
      # Loop cutting edges an look for bounded faces that are "inside" the
      # cutting edge.
      cut_away_faces = []
      cutting_edges.each do |e|
      
        # Edge can be marked as deleted if merged with another edge.
        next unless e.valid?
        
        edge_points = e.vertices.map { |v| v.position }
        matches_as_non_reversed = cutting_edge_points.include?(edge_points)
        matches_as_reversed = cutting_edge_points.include?(edge_points.reverse)
        
        # If edge has been split it doesn't match any pair of points and no
        # face can be found from it. If any of the edges of a loop is intact
        # all faces inside will be found later on.
        next unless matches_as_non_reversed || matches_as_reversed
        next if matches_as_non_reversed && matches_as_reversed
        
        reversed = matches_as_reversed
        e.faces.each do |face|
          cut_away_faces << face if e.reversed_in?(face) == reversed
        end
      end
      
      # REVIEW: If cutting edges doesn't form closed loops on the existing
      # mesh the whole mesh gets cut away. Also happens if any face is faulty
      # oriented along loop. Loop should be validated and face crawler thing
      # must be more stable.
      
      # Traverse faces by shared binding edge that isn't a cut edge to find
      # all faces inside a loop and hide them.
      cut_away_faces = EneBuildings.connected_faces cut_away_faces, cutting_edges

      cut_away_edges = cut_away_faces.map { |f| f.edges }.flatten.uniq
      cut_away_edges.keep_if { |e| (e.faces - cut_away_faces).empty? }
      
      cut_away_faces.each { |f| f.hidden = true }
      cut_away_edges.each { |f| f.hidden = true }
      
    end

    nil

  end

  # Public: Tells if any solid operations can be performed on Building (based on
  # template).
  #
  # Called when opening properties dialog to enable or disable the setting for
  # performing solid operations.
  #
  # Returns true or false.
  def has_solids?

    @template.has_solids?

  end

  # Public: list replaceable groups/components (based on how building is drawn).
  # Groups and components in the building segments can have attributes telling
  # they can be optionally replaced by other groups/components, for instance a
  # door replacing a window.
  #
  # Called when opening properties dialog to allow user to set what to replace
  # with what.
  #
  # Returns array# TODO: COMPONENT REPLACEMENT: what does array contain?
  def list_replaceable_components

    # TODO: COMPONENT REPLACEMENT: get data from template and from var stored on last draw_basic.
    # Return array like:
    # [
    #   {
    #     :name => String, used to identify original component #(from template)
    #     :replacement => [             #(from template)
    #       {
    #         :name => String, used to identify group/component.
    #         :slots => Fixnum, how many slot this replacement requires (from template)
    #       }
    #     ]
    #     :slots/available_slots = [    #(from last draw_basic)
    #       Fixnum, slots (number of original component) in first segment
    #       Fixnum, slots (number of original component) in second segment...
    #   }...
    # ]

  end

  # Public: List replaceable materials (based o template).
  # Materials directly in segment groups are listed. Materials in nested groups
  # are also listed if the group has an attribute specifically saying so.
  #
  # Called when opening properties dialog to allow user to set what materials
  # to replace with what other materials.
  #
  # Returns array of Material objects.
  def list_replaceable_materials

    @template.list_replaceable_materials

  end

  # Public: [Re-]Load class instance variables from group attributes.
  # Unknown (not installed) template will be nil.
  #
  # Returns nothing.
  def load_attributes

      # Loop group attributes and save as object attribute.
      @group.attribute_dictionary(ATTR_DICT).each_pair do |key, value|
        instance_variable_set("@" + key.to_s, value)
      end
      
      # Set back_along_path to false if not already set for backward
      # compatibility. The value nil is reserved to let PathHandling handle
      # paths where back_along_path doesn't make any sense, e.g. plots instead
      # of individual buildings.
      @back_along_path ||= false

      # Override template id string with reference to actual object.
      #nil if not found.
      @template = Template.get_from_id @template

      # Override material replacement string identifiers with actual material
      # references.
      model_materials = @group.model.materials
      @material_replacement = (@material_replacement || []).map do |p|
        p.map{ |name| model_materials[name] }
      end
      # Delete replacement pair if replacer is nil. Replacer material becomes
      # nil if it has been deleted from model.
      @material_replacement.delete_if { |p| !p[1] }

  end

  # Public: Check if template isn't missing.
  # If template is missing a the template select panel opens up to let user 
  # pick another template to use instead for this building.
  #
  # Yields if template was missing but user chose to pick a new one instead.
  #
  # Examples
  #
  #   def my_method(building)
  #     # If there is no valid_template, call same method again after once
  #     # user has selected a new template.
  #     return unless building.valid_template? { my_method(building) }
  #     # Do stuff with building here.
  #     p building.template
  #   end
  #
  # Returns true if template can be found and nil if it's missing.
  def valid_template?(&block)

    return true if @template
    return false unless block

    missing = @group.get_attribute ATTR_DICT, "template", "nil"
    msg =
      "The template '#{missing}' used on this building could not be found.\n"\
      "Perhaps building was drawn on a computer with more templates installed.\n\n"\
      "Choose new template?"
    return false if UI.messagebox(msg, MB_OKCANCEL) == IDCANCEL

    Template.select_panel("Replace missing template") do |t|
      next unless t
      @template = t
      block.call
    end

    false

  end

  # Public: Open web dialog and let user set Building properties.
  # Template, material replacement and component replacement among others can be
  # set.
  #
  # When changing values in the form the Building object attributes are directly
  # changed. These changes are not saved to the Group if user cancels but still
  # exist in the Building object.
  #
  # Do not use the same Building object at a later point, instead initialize a
  # new from the group as this:
  #   b = Building.new b.group
  #
  # REVIEW: Do not instantly change Building object. Change it once user saves.
  #
  # Returns WebDialog object.
  def properties_panel

    # Only allow one properties dialog for each building at a time.
    # References to opened properties dialogs are saved as a hash indexed by the
    # guid of the group.
    @@opened_dialogs ||= {}
    dlg = @@opened_dialogs[@group.guid]
    if dlg
      dlg.bring_to_front
      return dlg
    end

    # Check if template is known.
    # Model could be created on a computer that has more templates installed.
    return unless valid_template? { properties_panel }

    # Create dialog.
    dlg = UI::WebDialog.new("Building Properties", false, "#{ID}_building_properties_panel", 610, 450, 100, 100, true)
    dlg.min_width = 440
    dlg.min_height = 300
    dlg.navigation_buttons_enabled = false
    dlg.set_file(File.join(PLUGIN_DIR, "dialogs", "building_properties_panel.html"))
    @@opened_dialogs[@group.guid] = dlg

    # Material and component replacement cannot run twice without redrawing the
    # original building from template in between to have the original content to
    # replace. This flag tells if the building group is "pure" (drawn by draw_basic
    # but no other draw methods). Assume this is false and set it to true when
    # changing template, thus redrawing the basics.
    pure = false

    # Reference to template dialog.
    # Used to make sure just one is opened from this properties dialog and to
    # close when this dialog closes.
    dlg_template = nil

    # Add data.
    add_data = lambda do

      js ="var preview_dir = '#{Template::PREVIEW_DIR}';"

      # If more dialogs are opened, offset this one to avoid it being on top of others
      js << "offset_window(10);" if @@opened_dialogs.size > 1

      # Template info.
      js << "var template_info=#{@template.json_data};"
      js << "update_template_section();";

      # Material replacement options (based on template component) and current
      # preferences (saved to building).
      material_pairs = list_replaceable_materials.map do |original|
        pair = @material_replacement.find { |e| e[0] == original}
        replacement = pair[1] if pair
        a = [
          {# Original to replace.
            :name => original.display_name,
            :id => original.name,
            :css_string => EneBuildings.material_to_css(original),
            :textured => !original.texture.nil?
          }
        ]
        a << {# Replace preference (if any is set).
          :name => replacement.display_name,
          :id => replacement.name,
          :css_string => EneBuildings.material_to_css(replacement),
          :textured => !replacement.texture.nil?
        } if replacement
        a
      end
      js << "var material_pairs=#{JSON.generate(material_pairs)};"
      js << "update_material_section();";

      # Component replacement...

      # <Hörntorn>...

      # Solids.
      js << "var has_solids = #{has_solids?};"
      js << "var perform_solids = #{@perform_solid_operations};"
      js << "update_solids_section();";

      dlg.execute_script js

    end

    # Show dialog.
    if Sketchup.platform == :platform_win
      dlg.show { add_data.call }
    else
      dlg.show_modal { dadd_data.call }
    end

    # Start operator.
    # This operator is committed when pressing OK or Apply and aborted when
    # pressing cancel.
    op_name = "Building Properties"
    @group.model.start_operation op_name, true
    
    # HACK: Make a temporary group to apply materials to to load them into
    # model.
    temp_material_group = @group.model.entities.add_group
    temp_material_group.visible = false
    temp_material_group.entities.add_cpoint ORIGIN

    # Closing dialog.
    # Cancels (Abort operation) unless called from "apply" callback.
    set_on_close_called_from_apply = false
    dlg.set_on_close do
      unless set_on_close_called_from_apply
        temp_material_group.erase!
        @group.model.abort_operation
      end

      # Close template selector if opened.
      dlg_template.close if dlg_template && dlg_template.visible?

      @@opened_dialogs.delete @group.guid
    end

    # Dialog buttons.
    
    model = @group.model

    # Clicking OK or apply.
    dlg.add_action_callback("apply") do |_, close|
      close = close == "close"

      # Call all draw methods.
      # Draw basic is included if group isn't "pure" (if it has been customized
      # since last draw_basic).
      draw nil, pure
      pure = false

      temp_material_group.erase!
      model.commit_operation

      if close
        set_on_close_called_from_apply = true
        dlg.close
      else
        model.start_operation op_name, true
      end
    end

    # Clicking cancel.
    dlg.add_action_callback("cancel") do
      dlg.close
    end

    # Changing values.

    # Open building template selector.
    dlg.add_action_callback("browse_template") do
      if dlg_template && dlg_template.visible?
        dlg_template.bring_to_front
      else
        dlg_template = Template.select_panel("Change Template", @template) do |t|
          next unless t
          next if t == @template
          @template = t
          # Redraw with new template so information about component placement can
          # be gathered.
          draw_basic
          pure = true

          # Update form.
          add_data.call
          dlg.bring_to_front
        end
      end
    end

    # Material replacement.
    dlg.add_action_callback("replace_material") do |_, original_string|
      original = model.materials[original_string]
      next unless original
      active_m = model.materials.current

      # Make sure active_m is added to model.
      temp_face = temp_material_group.entities.add_face(
        Geom::Point3d.new(rand, rand, rand),
        Geom::Point3d.new(rand, rand, rand),
        Geom::Point3d.new(rand, rand, rand)
      )
      temp_face.material = active_m
      active_m = temp_face.material

      # Save preference
      pair = @material_replacement.find { |e| e[0] == original}
      if pair
        # override replacement or remove if active material is nil.
          if active_m
            pair[1] = active_m
          else
            @material_replacement.delete pair
          end
      elsif active_m
        # Create replacement unless active material is nil.
        @material_replacement << [original, active_m]
      end

      # Update preview.
      json =
        if active_m
          JSON.generate({
            :name => active_m.display_name,
            :id => active_m.name,
            :css_string => EneBuildings.material_to_css(active_m),
            :textured => !active_m.texture.nil?
          })
        else
         "null"
        end
      # js = "update_material_section();"# Recreating whole list moves focus.
      js = "update_material_replacment('#{original_string}', #{json});"
      dlg.execute_script js
    end

    # Component replacement.
    #...

    # Corners
    #...

    # Gables
    #...

    # Solids
    dlg.add_action_callback("perform_solids") do |_, perform_solids|
      @perform_solid_operations = perform_solids == "true"
    end

    # Misc (UI stuff)

    # Open information website.
    dlg.add_action_callback("openUrl") do
    p @template.source_url
      UI.openURL @template.source_url
    end

    # Open material browser.
    dlg.add_action_callback("browse_materials") do
      UI.show_inspector "Materials"
    end

    # Set dialog position
    dlg.add_action_callback("set_position") do |_, callbacks|
      left, top = callbacks.split(",")
      dlg.set_position left.to_i, top.to_i
    end

    # Update style rule for hovered "apply material" button so thumbnail shows
    # the currently active material.
    # Runs when mouse enters document.
    dlg.add_action_callback("update_style_rule") do
    
      mat_string = EneBuildings.material_to_css model.materials.current
      js = "var selector = '#material_list button:hover div';"
      js << "var property = 'background';"
      js << "var value = \"#{mat_string} !important\";"
      js << "var stylesheet = document.styleSheets[1];"#0th stylesheet is linked, 1st is the embedded.
      js << "var rule_string = selector+'{'+property+':'+value+';}';"
      js << "var rule_index = stylesheet.cssRules.length;"
      js << "stylesheet.insertRule(rule_string, rule_index);"
      dlg.execute_script js

    end

    dlg

  end

  # Public: Saves the instance variables of the building object as attributes to
  # Group so they ca be retrieved when object is later re-initialized.
  # Called from draw.
  #
  # Returns nothing.
  def save_attributes

    # Add all class instance variables as group attributes.
    instance_variables.each do |key|
      next if key == :@group # Do not save group reference.
      value = instance_variable_get(key)
      key = key.to_s  # Make string of symbol
      key[0] = ""     # Remove @ sign from key
      @group.set_attribute ATTR_DICT, key, value
    end

    # Override template object reference with string.
    @group.set_attribute ATTR_DICT, "template", @template ? @template.id : nil

    # Override material replacements wit string identifiers.
    array = @material_replacement.map { |e| e.map{ |m| m.name } }
    @group.set_attribute ATTR_DICT, "material_replacement", array

    nil

  end

  # TODO: COMPONENT REPLACEMENT: make method that sets component replacements either randomly or from template preset. can be called from add building tool. do the same with materials.
  
end

end
