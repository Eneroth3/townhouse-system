EneBuildings::Template.require_all
building          = EneBuildings::Building.new
building.template = EneBuildings::Template.get_from_id "ene_landshovdingehus_reveterat"
building.path     = [ORIGIN, Geom::Point3d.new(45.m, 0, 0)]

start = Time.now

Sketchup.active_model.start_operation "Draw Building"
building.draw
Sketchup.active_model.commit_operation

UI.messagebox "Drawn in #{Time.now - start}s."