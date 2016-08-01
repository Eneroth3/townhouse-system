# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

  require "fileutils"
  require "json"

  unless Sketchup.version.to_i >= REQUIRED_SU_VERSION.to_i
    msg = "#{NAME} requires Sketchup version #{REQUIRED_SU_VERSION} or later to run."
    UI.messagebox msg
    raise msg
  end

  # Internal: Cursors used by tools.
  CURSOR_ARROW       = UI.create_cursor File.join(PLUGIN_DIR, "cursors", "arrow.png"), 9, 9# TODO: prevent from covering tooltip but keep consistent to native cursors based on the select cursor.
  CURSOR_PEN         = UI.create_cursor File.join(PLUGIN_DIR, "cursors", "pen.png"), 1, 31
  CURSOR_PEN_INVALID = UI.create_cursor File.join(PLUGIN_DIR, "cursors", "pen_invalid.png"), 1, 31

  # Internal: Path to plugin's temp directory.
  PLUGIN_TEMP_DIR = File.join Sketchup.temp_dir, ID
  Dir.mkdir PLUGIN_TEMP_DIR unless File.exists? PLUGIN_TEMP_DIR

  # Internal: Path to material thumbnail directory.
  THUMBS_DIR = File.join PLUGIN_TEMP_DIR, "material_thumbnails"
  Dir.mkdir THUMBS_DIR unless File.exists? THUMBS_DIR

  # Internal: Resolution of material thumbnails.
  THUMB_RES = 18

  # Load all classes and modules.
  Sketchup.require File.join(PLUGIN_DIR, "lib", "zip")
  Sketchup.require File.join(PLUGIN_DIR, "observers")
  Sketchup.require File.join(PLUGIN_DIR, "my_geom")
  Sketchup.require File.join(PLUGIN_DIR, "my_view")
  Sketchup.require File.join(PLUGIN_DIR, "solids")
  Sketchup.require File.join(PLUGIN_DIR, "template")
  Sketchup.require File.join(PLUGIN_DIR, "building")
  Sketchup.require File.join(PLUGIN_DIR, "template_editor")
  Sketchup.require File.join(PLUGIN_DIR, "path_handling")
  Sketchup.require File.join(PLUGIN_DIR, "building_insert_tool")
  Sketchup.require File.join(PLUGIN_DIR, "building_position_tool")
  Sketchup.require File.join(PLUGIN_DIR, "menu")

  # Some general methods that don't really fit into any class or module.
  # REVIEW: Typically these would fit better as refinements to classes outside
  # this extension.

  # Internal: Get hash from attribute dictionary.
  #
  # entity    - The entity the dictionary is attached to.
  # dict_name - Name of the dictionary.
  # symbol    - Use Symbols instead of Strings as keys (default: true).
  #
  # Returns hash. Hash is empty if dictionary is empty or not found.
  def self.attr_dict_to_hash(entity, dict_name, symbol = true)

    h = {}
    ad = entity.attribute_dictionary(dict_name)
    return h unless ad
    ad.each_pair do |k, v|
      k = k.to_sym if symbol
      h[k] = v
    end

    h

  end

  # Internal: Copy all attributes from one entity to another.
  #
  # source - The entity which attributes should be copied.
  # target - The entity to copy attributes to.
  #
  # Returns nothing.
  def self.copy_attributes(source, target)

    ads = source.attribute_dictionaries || []
    #attribute_dictionaries returns nil instead of empty array when empty -_-.
    ads.each do |dict|
      dict.each_pair do |key, value|
        target.set_attribute(dict.name, key, value)
      end
    end

    nil

  end

  # Internal: Copy an instance with properties such as layer and attributes.
  #
  # old_instance       - The Group or ComponentInstance to copy.
  # new_entities       - The Entities object to place new instance in
  #                      (default: same as the original).
  # new_transformation - The Transformation of the new instance
  #                      (default: same as the original).
  #
  # Returns newly placed Group or ComponentInstance.
  def self.copy_instance(old_instance, new_entities = nil, new_transformation = nil)

    new_entities       ||= old_instance.entities
    new_transformation ||= old_instance.transformation

    instance          = new_entities.add_instance(
      old_instance.definition,
      new_transformation
    )
    instance.material = old_instance.material
    instance.layer    = old_instance.layer
    instance.name     = old_instance.name
    copy_attributes old_instance, instance

    instance

  end

  # Internal: Replaces component instance with similar group.
  #
  # component      - The ComponentInstance.
  # keep_component - Keep the original component (default: false).
  #
  # Returns Group.
  def self.component_to_group(component, keep_component = false)

    entities = component.parent.entities
    group    = entities.add_group
    group.transformation = component.transformation
    cd = component.definition
    temp_c = group.entities.add_instance cd, Geom::Transformation.new
    temp_c.explode
    copy_attributes component, group
    group.layer    = component.layer
    group.material = component.material
    group.name     = component.name
    component.erase! unless keep_component

    group

  end

  # Internal: compress directory to zip archive.
  # Creates archive if it doesn't already exist.
  #
  # files  - A single path or an array of paths of the files to compress.
  # target - Path to save archive to.
  #
  # Returns nothing.
  def self.compress(files, target)

    files = [*files]

    Zip::File.open(target, Zip::File::CREATE) do |zipfile|
      files.each do |file_path|
        file_name = File.basename file_path
        zipfile.add(file_name, file_path) { true }
      end
    end

    nil

  end

  # Internal: Find all faces connected by sharing bounding edges with faces.
  #
  # faces               - Array of Face objects to start with.
  # disconnecting_edges - Edges separates faces.
  #
  # Returns  Face Array.
  def self.connected_faces(faces, disconnecting_edges = [])

    faces = faces.dup

    while true

      binding_edges = faces.map { |f| f.edges }.flatten.uniq
      binding_edges -= disconnecting_edges

      break if binding_edges.empty?

      adjacent_faces = binding_edges.map { |e| e.faces }.flatten.uniq
      adjacent_faces -= faces

      break if adjacent_faces.empty?

      faces += adjacent_faces

    end

    faces

  end

  # Internal: Extract zip archive.
  #
  # source - Path to archive.
  # target - Path to directory to extract to.
  #
  # Returns nothing.
  def self.extract(source, target)

    Zip::File.open(source) do |zip_file|
      zip_file.each do |entry|
        entry.extract(File.join(target, entry.name))
      end
    end

    nil

  end

  # Internal: Suggest an ID in ansi characters based on an author prefix and a
  # name separated by underscore.
  #
  # Returns ID string.
  def self.make_id_suggestion(name, author)

    return if name.empty?
    return if author.empty?

    name = normalize_string name.downcase
    author = normalize_string author, true

    author_prefixes = Sketchup.read_default ID, "author_prefixes", []
    author_prefixes = Hash[*author_prefixes.zip().flatten]

    prefix =
      if author_prefixes[author]
        # If there's a saved prefix that's been used before by tis user, use it.
        author_prefixes[author]
      elsif author =~ / /
        # Otherwise, if name contains a space, use first letter in each word.
        # (e.g. Firstname Lastname -> FL)
        author.scan(/\b(\w)/).join
      elsif author =~ /[A-Z][a-z ]+[A-Z]/
        # Otherwise, if name contains more than one Uppercase character separated
        # by lowercase characters, use uppercase characters.
        # (e.g. CamelCase -> CC)
        author.scan(/([A-Z])/).join
      elsif author.length > 4
        # Otherwise, if name is longer than 4 characters, limit it that and use.
        author[0..3]
      else
        author
      end

    "#{prefix}_#{name}"

  end

  # Internal: Get a css-string for material preview.
  #
  # material - The material object.
  #
  # Returns a string that can be used in a css rule as background.
  def self.material_to_css(material)

    if !material
      "url(nil_material.png)"# HACK: should ideally have correct colors from RenderingOptions.
    elsif !material.texture
      color = material.color
      "rgb(#{color.red},#{color.green},#{color.blue})"
    else

      # Bake colors and other information into thumbnail file name to avoid
      # collision of edited materials between Sketchup models.
      basename = File.basename material.texture.filename
      color = material.color
      hash = (material.name + basename + color.to_a.join(" ")).hash
      name = "#{hash}_#{THUMB_RES}.png"
      filename = File.join THUMBS_DIR, name

      unless File.exist? filename
        # FIXME: Colorize thumbnail when supported by SU or use third party library.
        material.write_thumbnail filename, THUMB_RES
      end

      "url('file:///#{filename}')"

    end

  end

  # Internal: Find edges that's only binding one face.
  #
  # entities - An Entities object or an Array of Entity objects.
  #
  # Returns an Array of Edges.
  def self.naked_edges(entities)

    entities = entities.to_a

    entities.select { |e| e.is_a?(Sketchup::Edge) && e.faces.size == 1 }

  end

  # Internal: Remove special characters from string.
  # Accents are replaced by the corresponding a-z character.
  #
  # string      - The original string that may contain special characters.
  # allow_space - Whether spaces should be kept pr replaced by underscores.
  #
  # Returns a string with no special characters
  # (only A-Z, a-z, 0-9, underscores, dots and optionally spaces).
  def self.normalize_string(string, allow_space = false)

    string.tr!(
      "ÀÁÂÃÄÅàáâãäåÇçCcCcCcCcÐðDdÐdÈÉÊËèéêëÌÍÎÏìíîïÑñNnNnNnÒÓÔÕÖØòóôõöøŠšÙÚÛÜùúûüÝýÿYyŸZzZzŽž",
      "AAAAAAaaaaaaCcCcCcCcCcDdDdDdEEEEeeeeIIIIiiiiNnNnNnNnOOOOOOooooooSsUUUUuuuuYyyYyYZzZzZz"
    )
    string.tr!(" ", "_") unless allow_space
    string.gsub!(/\W/, "")

    string

  end

  # Internal: Open a directory in file browser.
  #
  # path - Path to directory.
  #
  # Returns nothing.
  def self.open_dir(path)

    if Sketchup.platform == :platform_win
      path = path.gsub "/", "\\"
      system("explorer.exe \"#{path}\"")
    else
      system("open \"#{path}\"")
    end

    nil

  end

  # Open plugin temp directory in file browser.
  #
  # Returns nothing.
  def self.open_temp_dir

    EneBuildings.open_dir PLUGIN_TEMP_DIR

    nil

  end

  # Internal: List all points in entities.
  #
  # entities - An Entities object, and Entity or an array of these.
  #
  # Returns Array of Points3d objects.
  def self.points_in_entities(entities)

  # Make entities an array of drawing elements.
  entities = entities.to_a if entities.is_a?(Sketchup::Entities)
  entities = [entities] if entities.is_a?(Sketchup::Drawingelement)

  recursive = lambda do |ents|
    pts = []
    ents.each do |e|
      if e.respond_to? :vertices
        pts += e.vertices.map { |v| v.position }
      elsif e.respond_to?(:definition)
        t = e.transformation
        pts += recursive.call(e.definition.entities).map { |p| p.transform t }
      end
    end
    pts
  end

  pts = recursive.call entities
  pts.uniq! { |a| a.to_a }

  pts

  end

  # Internal: Reload whole extension (except loader) without littering
  # console. Inspired by ThomTohm's method.
  #
  # Returns nothing.
  def self.reload

    # Hide warnings for already defined constants.
    old_verbose = $VERBOSE
    $VERBOSE = nil

    # Load
    Dir.glob(File.join(PLUGIN_DIR, "*.rb")).each { |f| load f }

    $VERBOSE = old_verbose

    nil

  end

  # Internal: Save the prefix used for an ID by a specific author so it can
  # later be retrieved by make_id_suggestion.
  #
  # Returns nothing.
  def self.save_author_prefix(author, prefix)

    return if author.empty?
    return if prefix.empty?

    author_prefixes = Sketchup.read_default ID, "author_prefixes", []
    author_prefixes = Hash[*author_prefixes.zip().flatten]
    author_prefixes[author] = prefix
    Sketchup.write_default ID, "author_prefixes", author_prefixes.to_a

    nil

  end

end
