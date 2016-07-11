# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

# Usage:
#   Menu:
#     Extensions > Eneroth Townhouse System,
#   Toolbars:
#     Eneroth Townhouse System
#     Eneroth Townhouse System Template Editing
#   Main building commands (available in menu and first toolbar):
#     Add Building:        Draw new building to model.
#     Building Position:   Reposition buildings by changing their path and end angles.
#     Building Properties: Open properties window for selected building.
#   Template editing commands (available in sub-menu and second toolbar):
#     New Template:  Create a new template component from the selected entities.
#     Open Template: Load template component from library for editing.
#     Save Template: Save template component to library.
#     Template Info: Set template information such as name, ID and built year.
#     Part Info:     Set part information such as positioning within building.
#     Open Template Directory (Menu only): Open folder templates are saved too.
#     Documentation (Menu only): Instructions regarding creating templates.
#
# For more information regarding the tools, check the instructor.
# Also keep an eye on the statusbar while using the tools.

# Requirements
#   Sketchup 2015+
#   IE 9+ makes dialogs look as desired* (Only apply to Windows)
#
# *Yup, SU on Windows uses IE to render web dialogs no matter what your
# default browser is.

# TODO
#   Better preview images with thinner nicer looking edges.
#   Component replacement. E.g. a certain windows can be replaced by doors.
#   More buildings!

# Known issues
#  In SU 2015 template parts cannot be copied while Part Info dialog is opened
#    due to dark observer magic.

# Load support files.
require "extensions.rb"
require "sketchup.rb"

# Public: Classes and methods used to draw buildings.
#
# Most of the code is a public API that can be called from external plugins,
# e.g. to create a whole city.
#
# Examples
#
#   EneBuildings::Template.require_all
#   path = [Geom::Point3d.new, Geom::Point3d.new(10.m, 0, 5.m)]
#   random_template = EneBuildings::Template.instances.sample
#
#   building = EneBuildings::Building.new
#   building.path = path
#   building.template = random_template
#
#   Sketchup.active_model.start_operation "Draw Building"
#   building.draw
#   Sketchup.active_model.commit_operation
#  
module EneBuildings

  # Public: General extension information.
  AUTHOR      = "Julia Christina Eneroth"
  CONTACT     = "#{AUTHOR} at eneroth3@gmail.com"
  COPYRIGHT   = "#{AUTHOR} #{Time.now.year}"
  DESCRIPTION =
    "Draw townhouses precisely after their plots no matter its shape. "\
    "Can be used from anything to city planning to game making."
  ID          =  File.basename __FILE__, ".rb"
  NAME        = "Eneroth Townhouse System"
  VERSION     = "1.0.0"
  
  # Public: Minimum Sketchup version required to run plugin.
  REQUIRED_SU_VERSION = "15"

  # Public: Path to loader file's directory.
  PLUGIN_ROOT = File.expand_path(File.dirname(__FILE__))

  # Public: Path to plugin's own directory.
  PLUGIN_DIR = File.join PLUGIN_ROOT, ID

  # Create Extension once required gems are installed.
  ex = SketchupExtension.new(NAME, File.join(PLUGIN_DIR, "main"))
  ex.description = DESCRIPTION
  ex.version     = VERSION
  ex.copyright   = COPYRIGHT
  ex.creator     = AUTHOR
  Sketchup.register_extension ex, true

end
