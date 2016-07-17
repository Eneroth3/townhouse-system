# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

# Public: A Template is what a Building is based on when drawn.
#
# Each template is saved as a zip archive containing a Sketchup model with
# geometry and drawing instructions, a JSON text file of additional information
# and preview images.
# All buildings (that have been drawn) have an associated template.
class Template

  # IDEA: Loading templates from component definition already in model.
  # This could be done in addition to loading templates from the template
  # directory similar to how the component browser handles components
  # "In model" even if they are not saved to the library.
  #
  # All template data (json-data + images) could be saved to the component
  # definition when loaded (not to the skp file itself since that would mean
  # duplicated in the template archive file).
  #
  # This data could also be used to re-create a template archive file from the
  # component definition (similar to dragging a component from "In model" to a
  # library). There could also be an option to enter new template information
  # and save an edited version of the component as a new template.

  # Allow sorting of templates.
  include Comparable

  # Public: Name of attribute dictionary used for positioning of
  # groups/components inside building.
  ATTR_DICT_PART = "#{ID}_part"

  # Public: Prefix before template id in component names.
  COMPONENT_NAME_PREFIX = "#{NAME}: "
  
  # Public: Building depth to use in certain cases for template without a defined
  # depth, e.g. setting end rotation handle lengths in tools.
  FALLBACK_DEPTH = 10.m
  
  # Public: The file extension used by this template.
  FILE_EXTENSION = "bldg"

  # Public: Directory for preview images of all loaded templates.
  # Each template has a square preview (100*100px) and a landscape golden
  # rectangle preview (200*124px).
  #
  # These images can be read (e.g. shown in custom web dialogs) but nothing
  # should be written to this directory from outside this plugin itself.
  PREVIEW_DIR = File.join PLUGIN_TEMP_DIR, "previews"
  Dir.mkdir PREVIEW_DIR unless File.exists? PREVIEW_DIR
  
  # Public: Path to 100 px wide template preview placeholder image.
  PREVIEW_PLACEHOLDER_100 = File.join PLUGIN_DIR, "dialogs", "template_placeholder_100.png"
  
  # Public: Path to 200 px wide template preview placeholder image.
  PREVIEW_PLACEHOLDER_200 = File.join PLUGIN_DIR, "dialogs", "template_placeholder_200.png"

  # Public: Path to template directory.
  # If you add a new template file you can load it by calling
  # "Template.new <id>", where <id> is the basename of the file (file name
  # without extension).
  TEMPLATE_DIR = File.join PLUGIN_DIR, "building_templates"

  # Internal: Temporary directory used when reading archives.
  EXTRACT_DIR = File.join PLUGIN_TEMP_DIR, "extract"
  Dir.mkdir EXTRACT_DIR unless File.exists? EXTRACT_DIR
  
  # Internal: Vector to point camera in when making template previews.
  PREVIEW_CAM_VECTOR = Geom::Vector3d.new -1, 1, 0
  
  # Internal: Field of view (in degrees) for preview camera.
  PREVIEW_FOV = 35

  # Internal: How much larger images should be rendered to avoid thick ugly
  # edges.
  PREVIEW_RESIZE_FACTOR = 3

  # Internal: Statusbar text.
  STATUS_LOADING = "Loading template for first use... (This may take a few seconds)"
  STATUS_DONE_LOADING = "Done loading."

  @@loaded ||= false

  @@instances ||= []
  
  # HACK: Automatically seize previews with library instead.
  # Remember to remove hack entry from menu.
  @@manually_resize_previews = false unless defined? @@manually_resize_previews
  
  # Class variable accessors

  # Public: Tells if templates has been loaded for this SU session.
  # Templates are not loaded until they are needed to speed up startup.
  def self.loaded; @@loaded; end

  # Public: Returns instances array.
  def self.instances; @@instances; end
  
  # Internal: Whether user should manually downsample preview images.
  def self.manually_resize_previews; @@manually_resize_previews; end
  def self.manually_resize_previews=(v); @@manually_resize_previews = v; end

  # Class methods

  # Public: Check if an object is a ComponentInstance representing a Template.
  #
  # entity - The object to test.
  #
  # Returns true if ComponentInstance represents a template, otherwise false.
  def self.component_is_template?(entity)
  
    return false unless entity.is_a?(Sketchup::ComponentInstance)
    return false unless entity.definition.name.start_with? COMPONENT_NAME_PREFIX
    
    true
    
  end
  
  # Public: Get filename of template file for specific template ID.
  #
  # id - The ID of the template.
  #
  # Returns String filename.
  def self.filename(id)
  
    id + "." + FILE_EXTENSION
    
  end
  
  # Public: Get full path of template file for specific template ID.
  #
  # id - The ID of the template.
  #
  # Returns String path.
  def self.full_path(id)
  
    File.join TEMPLATE_DIR, filename(id)
    
  end
  
  # Public: Get Template object that uses a given component definition.
  #
  # component_def - a ComponentDefinition object.
  #
  # Returns Template object or nil if not found.
  def self.get_from_component_definition(component_def)
  
    name = component_def.name
    return unless name.start_with? COMPONENT_NAME_PREFIX
   
    @@instances.find { |h| h.component_name == name }
    
  end
  
  # Public Get Template object from given template id.
  #
  # id - Id String.
  #
  # Returns Template object or nil if not found.
  def self.get_from_id(id)

    @@instances.find { |h| h.id == id }

  end

  # Public: [Re-]Load all templates from building templates directory.
  #
  # Returns nothing.
  def self.load_all

    files = Dir.glob(File.join(TEMPLATE_DIR, "*.#{FILE_EXTENSION}"))

    files.each do |file|
      id = File.basename file, ".*"
      load_id id
      # IDEA: add reload-button in select panel? requires removed templates to be unloaded (purged).
    end

    @@loaded = true

    nil

  end

  # Public: [Re]load a template by a specific id and create object for it.
  # If a template by that id is already created, reload its data into existing
  # object.
  #
  # id - The id of the template, same as the basename of its file excluding
  #      extension.
  #
  # Returns Template.
  def self.load_id(id)

    t = get_from_id id
    if t
      t.load_data
    else
      t = new id
    end

    t

  end

  # Open template directory in file browser.
  def self.open_dir

    EneBuildings.open_dir TEMPLATE_DIR

  end

  # Public: Load all installed templates unless they have already been loaded.
  # Called when building object is created and select_panel is opened.
  # By waiting to load templates until they are needed Sketchup startup is
  # sped up.
  #
  # Returns nothing.
  def self.require_all

    load_all unless @@loaded

    nil

  end

  # Public: Open a web dialog and let user select building template.
  #
  # title    - Title of dialog window (default: "Select Building Template").
  # selected - Template to already be selected when dialog opens (default nil).
  # instant  - Disable OK button and run block as soon as a template is clicked
  #            as opposed to when user clicks OK (default: false).
  #
  # Examples
  #
  #  select_panel("Select a template") { |template| puts "Template is #{template}" }
  #
  # Yields Template object or nil if user cancels.
  #
  # Returns WebDialog object.
  def self.select_panel(title = "Select Building Template", selected = nil, instant = false, &block)

    # Load templates unless they have already been loaded.
    require_all

    # Assume user didn't click OK until they do.
    status = false

    # Create dialog.
    dlg = UI::WebDialog.new(title, false, "#{ID}_template_select_panel", 360, 450, 100, 100, true)
    dlg.min_width = 250
    dlg.min_height = 250
    dlg.navigation_buttons_enabled = false
    dlg.set_file(File.join(PLUGIN_DIR, "dialogs", "template_select_panel.html"))

    # Add data.
    js ="var preview_dir = '#{PREVIEW_DIR}';"
    js << "var templates=["
    @@instances.sort.each do |t|
      js << t.json_data
      js << ","
    end
    js.chomp! unless @@instances.empty?
    js << "];"
    js << "var selected='#{selected ? selected.id : "null"}';"
    js << "var sorting='#{Sketchup.read_default(ID, "template_sorting", "0")}';"
    js << "var grouping='#{Sketchup.read_default(ID, "template_grouping", "country")}';"
    if instant
      js << "document.getElementById('buttons_not_instant').style.display='none';"
    else
      js << "document.getElementById('buttons_instant').style.display='none';"
    end
    js << "set_dropdowns();"
    js << "view_list();"

    # Show dialog.
    if Sketchup.platform == :platform_win
      dlg.show { dlg.execute_script js }
    else
      dlg.show_modal { dlg.execute_script js }
    end

    # Clicking OK, cancel or close.
    dlg.add_action_callback("close") do |_, callbacks|
      status = callbacks == "true"
      dlg.close
    end

    # On dialog close.
    dlg.set_on_close do
      yield_var = status ? selected : nil
      block.call(yield_var) if block && !instant
    end

    # Clicking on building template.
    dlg.add_action_callback("select") do |_, id|
      selected = @@instances.find{ |t| t.id == id }
      block.call(selected) if block && instant
    end

    # Save sorting and grouping.
    dlg.add_action_callback("save_sorting_n_grouping") do |_, callbacks|
      callbacks = callbacks.split "&"
      Sketchup.write_default ID, "template_sorting", callbacks[0]
      Sketchup.write_default ID, "template_grouping", callbacks[1]
    end

    # Open template folder.
    dlg.add_action_callback("open_dir") do
      open_dir
    end

    dlg

  end

  # Public: Check if a component definition is valid for representing a
  # template. A template component must contain 2 gable faces, one with
  # positive X axis as normal and one with negative X axis as normal.
  # All other loose faces should be perpendicular to these two.
  #
  # Returns boolean.
  def self.valdiate_component?(component_definition)

    ents = component_definition.entities
    faces_l = ents.select { |e| e.is_a?(Sketchup::Face) && e.normal.samedirection?([-1,0,0]) }
    faces_r = ents.select { |e| e.is_a?(Sketchup::Face) && e.normal.samedirection?([1,0,0]) }
    
    # TODO: TEMPLATE VALIDIATION: check if all other loose faces are perpendicular to these /has normal x == 0)
    # Check if main volume is solid when using solid operations.
    # Part names must be unique!
    
    faces_l.size == 1 && faces_r.size == 1
    
  end
  
  # Internal: Resets previous camera after preview camera has been used.
  # Must run after set_preview_camera.
  #
  # Returns nothing.
  def self.reset_camera

    unless defined? @@old_camera
      raise "set_preview_camera must be called before reset_camera."
    end

    model = Sketchup.active_model
    view = model.active_view
    cam = view.camera

    cam.set @@old_camera[:eye], @@old_camera[:target], @@old_camera[:up]
    cam.perspective = @@old_camera[:perspective]
    if @@old_camera[:perspective]
      cam.fov = @@old_camera[:fov_or_height]
    else
      cam.height = @@old_camera[:fov_or_height]
    end
    cam.aspect_ratio = @@old_camera[:aspect_ratio]

    nil

  end

  # Internal: Set camera angle and field of view to what is used for previews.
  # Camera eye position needs to be set separately to fit content.
  #
  # Returns nothing.
  def self.set_preview_camera

    model = Sketchup.active_model
    view = model.active_view
    cam = view.camera

    # Backup old camera so it can be reset.
    @@old_camera = {
      :eye           => cam.eye,
      :target        => cam.target,
      :up            => cam.up,
      :perspective   => cam.perspective?,
      :fov_or_height => cam.perspective? ? cam.fov : cam.height,
      :aspect_ratio  => cam.aspect_ratio
    }

    # Set new camera position.
    new_target = cam.eye.offset PREVIEW_CAM_VECTOR
    cam.set cam.eye, new_target, Z_AXIS
    cam.fov = PREVIEW_FOV

    nil

  end

  # Instance attribute accessors
  
  # Public: Returns 2 element array of what front and back side is aligned to.
  #   nil - Unspecified
  #   0   - Street
  #   1   - Courtyard
  #   2   - Firewall
  attr_reader :alignemnt

  # Public: Returns the template's architect or nil if not set.
  # Typically this is unknown for older buildings of this type.
  attr_reader :architect

  # Public: Returns the country template is built in or nil if not set.
  attr_reader :country

  # Public: Length between front and back side or nil if not set.
  attr_reader :depth
  
  # Public: Returns the description of the template or nil if not set.
  attr_reader :description

  # Public: Returns id string of template.
  attr_reader :id

  # Public: Returns the modeler of the template or nil if not set.
  attr_reader :modeler

  # Public: Returns the name of the template (same as id if not specifically
  # set).
  attr_reader :name

  # Public: Returns the source the modeler has used, e.g. a book,
  # or nil if not set.
  attr_reader :source

  # Public: Returns the source URL or nil if not set.
  attr_reader :source_url

  # Public: Returns the number of stories or nil if not set.
  attr_reader :stories

  # Public: Returns the year template was built or nil if not set.
  attr_reader :year

  # Instance methods

  # Public: Load a new Template object from library.
  #
  # id - The id string of the template to load.
  #      This is the same as the basename of the template file.
  def initialize(id)

    @id = id

    # Load data from JSON file add save as attributes.
    status = load_data

    # Add object to template list if data could be loaded.
    @@instances << self if status

  end

  # Public: Comparison for sorting.
  #
  # other - Other template to compare with.
  #
  # Returns -1 if self is smaller than other, 1 if self is greater than other
  # and 0 if equal.
  def <=>(other)

    @name <=> other.name

  end

  # Public: Reference to component definition used by this template.
  # Loads component definition if not already loaded.
  # The component definition is loaded when needed and NOT when loading the
  # template data and creating the template object.
  #
  # Returns ComponentDefinition.
  def component_def
        
    name = component_name
    
    # If component definition is already loaded, return it.
    definitions = Sketchup.active_model.definitions
    component_def = definitions.find { |cd| cd.name == name }
    return component_def if component_def
    
    # Otherwise load and return it.
    Sketchup.status_text = STATUS_LOADING
    read_archive do
    
      # Definitions.load cannot load multiple definitions from the same file
      # path. The latter will replace the previous definition in model.
      # Therefore use a temporary name while loading the external model.
      path = File.join(EXTRACT_DIR, "model.skp")
      temp_path = File.join(EXTRACT_DIR, "#{@id}_#{Time.now.to_i}.skp")
      File.rename path, temp_path
      component_def = definitions.load temp_path
      component_def.name = name
      
      # Make sure loaded component has the correct name.
      # If an older version of it was already loaded and had the name associated
      # with this template they should switch name-
      # TODO: NOT YET SUPPORTED: Purge old version if there are no instances of it.
      unless component_def.name == name
        name_with_number = component_def.name
        old_def = component_def.model.definitions[name]
        if old_def
          component_def.name ="#{name}_temp"
          old_def.name = name_with_number
        end
        component_def.name = name
      end
    
    end
    Sketchup.status_text = STATUS_DONE_LOADING
    
    component_def
      
  end
  
  # Public: Returns the name that the component definition used to draw
  # buildings with this template should.
  #
  # Returns name String.
  def component_name
  
    COMPONENT_NAME_PREFIX + @id
    
  end
  
  # Public: Get filename of template file.
  #
  # Returns String filename.
  def filename
  
    @id + "." + FILE_EXTENSION
    
  end
  
  # Public: Get full path of template file.
  #
  # Returns String path.
  def full_path
  
    File.join TEMPLATE_DIR, filename
    
  end
  
  # Public: Checks if there are any groups/components that can be used as
  # corners in building.
  def has_corners?

    component_def.entities.any? do |e|
      e.get_attribute(ATTR_DICT_PART, "corner") && e.get_attribute(ATTR_DICT_PART, "name")
    end

  end

  # Public: Checks if there are any groups/components that can be used as
  # gables in building.
  def has_gables?

    component_def.entities.any? do |e|
      e.get_attribute(ATTR_DICT_PART, "gable") && e.get_attribute(ATTR_DICT_PART, "name")
    end

  end

  # Public: Checks if there are any groups/components that can be used to
  # perform solid operations on building, e.g. cut an opening to the courtyard.
  def has_solids?

    component_def.entities.any? do |e|
      e.get_attribute(ATTR_DICT_PART, "solid")
    end

  end

  # Public: [Re-]Loads data for template JSON and save as attributes to self.
  #
  # Returns true on success and false on load error.
  def load_data

    read_archive do

      json = File.read(File.join(EXTRACT_DIR, "info.json"))
      begin
        hash = JSON.parse json
      rescue JSON::ParserError => e
        msg =
          "Template '#{@id}' could not be loaded due to invalid json.\n\n"\
          "Error message:\n#{e.message}"
          puts
        UI.messagebox msg
        return false
      end
      hash.each_pair do |key, value|
        # Keys not present in JSON will be regarded nil in ruby.
        instance_variable_set("@" + key.to_s, value)
        # FIXME: if template is reloaded after depth has been changed from length to nil old value is still loaded.
      end

      # If no name is supplied in JSON file, inherit id.
      @name ||= @id
      
      # Make depth Length.
      # Depth is saved as float in json.
      
      # Extension failed Extension Warehouse review for publishing because of an
      # error parsing depth as length that I cannot reproduce. Also the review
      # feedback is sent from a f*****g no-reply account so I cannot get more
      # information from the reviewer. Trying again with extra error handling.
      if @depth
        begin
          @depth = @depth.to_l
        rescue ArgumentError
            msg =
            "Template '#{@id}' could not be loaded due to invalid building depth.\n\n"\
            "Error message:\n#{e.message}"
            puts
          UI.messagebox msg
          return false
        end
      end

    end

    true

  end

  # Public: List replaceable materials.
  # Materials directly in template root are listed. Material in nested groups
  # are also listed if the group has an attribute specifically saying so.
  #
  # Returns array of Material objects.
  def list_replaceable_materials

    # Recursive material lister.
    # Lists as materials in context and in all nested groups with an attribute
    # specifically telling it to do so.
    recursive = lambda do |entities|
      materials = []
      entities.each do |e|
        materials << e.material if e.respond_to?(:material)
        if e.is_a?(Sketchup::Group) &&
           e.get_attribute(ATTR_DICT_PART, "replace_nested_mateials")
          materials += recursive.call(e.entities)
        end
      end

      materials
    end

    # Look for materials in all groups in template root
    recursive.call(component_def.entities).flatten.uniq.compact

  end

  # Public: Update template preview images.
  #
  # HACK: To create a preview of a buildings drawn with the template and not
  # the raw template an operation that empties the whole model only to be
  # aborted when the images are ready is performed. DO NOT run this inside
  # another operator.
  #
  # Returns nothing.
  def update_preview
    
    model = Sketchup.active_model
    view = model.active_view
    entities = model.entities
    selection = model.selection
    ro = model.rendering_options
    
    # Remember selection so currently selected entities can be re-selected.
    # If drawing context is inside the template component entities objects are
    # safely kept when creating previews. If in model root entities object gets
    # invalid because they are temporarily deleted when making previews. Then
    # use GUIDs instead.
    if model.active_path
      old_selection_entities = selection.to_a
    else
      old_selection_guids = selection.map { |e| e.respond_to?(:guid) && e.guid}
      old_selection_guids.compact!
    end
    
    Observers.disable
    
    # Start operator that can then be aborted so model isn't affected.
    model.start_operation "PREVIEW"
    
    # Go to top drawing context.
    model.close_active while model.active_path
    
    # Clear model.
    entities.clear!
    
    # Get building length from main volume of template component.
    face_left   = component_def.entities.find { |e| e.is_a?(Sketchup::Face) && e.normal.samedirection?(X_AXIS.reverse) }
    face_right  = component_def.entities.find { |e| e.is_a?(Sketchup::Face) && e.normal.samedirection?(X_AXIS) }
    point_left  = face_left.vertices.first.position
    point_right = point_left.project_to_plane face_right.plane
    length = point_left.distance point_right
    
    # Draw building with given template.
    p = [ORIGIN, Geom::Point3d.new(length, 0, 0)]
    b = Building.new
    b.template = self
    b.path = p
    b.draw false
    
    # Hide parts under ground level and set background color.
    # Change rendering options and backup existing options.
    new_ro = {}
    white = Sketchup::Color.new "White"
    new_ro["BackgroundColor"] = white
    new_ro["DrawGround"] = true
    new_ro["DrawUnderground"] = false
    new_ro["GroundColor"] = white
    new_ro["GroundTransparency"] = 0
    new_ro["SkyColor"] = white # There is no option to disable sky.
    old_ro = {}
    new_ro.each_pair do |k, v|
      old_ro[k] = ro[k]
      ro[k] = v
    end
    
    # Set camera vector.
    self.class.set_preview_camera
        
    # Images.
    images = [
      ["preview_100.png", 100, 100],
      ["preview_200.png", 200, 124]
    ]
    
    paths = []
    images.each do |i|
      name, width, height = i
      
      view.camera.aspect_ratio = width/height.to_f
      zoom_to_pts = EneBuildings.points_in_entities b.group
      zoom_to_pts = zoom_to_pts.each do |p|
        p.z = [p.z, 0].max
      end
      MyView.zoom_content view, zoom_to_pts, 0.04
      
      if @@manually_resize_previews
        width  *= PREVIEW_RESIZE_FACTOR
        height *= PREVIEW_RESIZE_FACTOR
      end
      
      # Export image.
      path = File.join EXTRACT_DIR, name
      paths << path
      options = {
       :filename => path,
       :width => width,
       :height => height,
       :antialias => true,
       :transparent => false
      }
      view.write_image options
    end
    
    # Abort operation and reset camera.
    model.abort_operation
    self.class.reset_camera
    old_ro.each_pair { |k, v| ro[k] = v }
    
    # Tell user to scale down images manually if not at correct size.
    if @@manually_resize_previews
      msg =
        "Images are rendered at a large scale to prevent thick ugly lines "\
        "and need to be manually scaled down by a factor #{PREVIEW_RESIZE_FACTOR}."
      UI.messagebox msg
      EneBuildings.open_dir EXTRACT_DIR
      UI.messagebox "Press OK when images are resized and saved."
    end
    
    # Save images to the template's archive file.
    write_to_archive paths
    
    # Move images to preview temp folder used by web dialogs.
    paths.each do |old_path|
      basename = File.basename old_path
      width = /preview_(\d+)\.png/.match(basename)[1]
      new_path = File.join PREVIEW_DIR, "#{@id}_#{width}.png"
      File.rename old_path, new_path
    end
        
    # Re-select previous selection.
    selection.clear
    if model.active_path
      # old_selection_entities contains entities selected inside template
      # component if it was opened. These entities do not get marked as deleted
      # when creating the previews since their drawing context isn't affected by
      #  it.
      old_selection_entities.reject! { |e| e.deleted? }
      selection.add old_selection_entities
    else
      # If user was in model root when creating previews the template component
      # instance has been deleted and cannot be re-selected from an entity
      # reference. Instead use GUID reference.
      to_reselect = entities.to_a.select do |e|
        e.respond_to?(:guid) && old_selection_guids.include?(e.guid)
      end
      selection.add to_reselect
    end
    
    # Update template editor's dialogs if opened.
    # This is called manually since Observers are disabled during the operation.
    TemplateEditor.load_info if TemplateEditor.info_opened?
    TemplateEditor.load_part_data if TemplateEditor.part_info_opened?
    
    Observers.enable
    
    nil

  end

  # Internal: List certain template data in JSON string to use for web dialogs.
  #
  # Returns JSON string.
  def json_data#TODO: have a to_hash method that makes a hash of all instance variable? Make JSON of that hash for dialogs. Use same hash when creating attributes in editor.

    json = "{"
    # List keys to include in JSON object here.
    %w(id name modeler architect country year stories source source_url description).each do |k|
      v = self.send k
      next if v.nil?
      # Escape to avoid HTML injection.
      v = v.gsub("<","&lt;").gsub(">","&gt;") if v.is_a? String
      # Use inspect to add quotes to strings but not numbers or booleans.
      json << "\"#{k}\":#{v.inspect},"
    end
    json.chomp!
    json <<" }"

    json

  end

  # Internal: Temporary decompresses template archive to EXTRACT_DIR so files
  # can be read. Also copies the preview images to the temp folder web dialogs
  # loads them from.
  #
  # Runs associated block and then empties temp directory when finished.
  #
  # Returns nothing.
  def read_archive
  
    # REVIEW: some of this stuff only applies to building templates and not templates generally.

    # Empty temp directory.
    FileUtils.rm_rf Dir.glob(File.join(EXTRACT_DIR, "*"))

    EneBuildings.extract full_path, EXTRACT_DIR

    # Copy images to web dialog directory.
    to_copy = Dir.glob(File.join(EXTRACT_DIR, "preview_*.png"))
    to_copy.each do |source|
      basename = File.basename source
      width = /preview_(\d+)\.png/.match(basename)[1]
      target = File.join PREVIEW_DIR, "#{@id}_#{width}.png"
      FileUtils.cp source, target
    end

    # Run code block.
    yield

    # Empty temp directory.
    FileUtils.rm_rf Dir.glob(File.join(EXTRACT_DIR, "*"))

    nil

  end

  # Internal: add given files to template archive.
  # Creates archive if it doesn't already exists.
  #
  # files - Array of String file paths to add to template archive file.
  #
  # Returns nothing.
  def write_to_archive(files)
  
    EneBuildings.compress files, full_path
    
    nil
    
  end

end

end
