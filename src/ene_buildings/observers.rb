# Eneroth Townhouse System

# Copyright Julia Christina Eneroth, eneroth3@gmail.com

module EneBuildings

# Internal: Wrapper for all observer related code in plugin.
# Concentrating observers here that actually has to do with different classes
# still is cleaner and easier to maintain than spreading out observers and
# code attaching them to new models.
module Observers
  
  # Whether observers are temporarily disabled or not.
  @@disabled = false

  # Keep track on active path length to differ entering from leaving.
  @@previous_path_size ||= 0
  
  def self.disabled?; @@disabled; end
  def self.disabled=(v); @@disabled = v; end
  def self.disable; @@disabled = true; end
  def self.enable; @@disabled = false; end
  
  def self.previous_path_size; @@previous_path_size; end
  def self.previous_path_size=(v); @@previous_path_size = v; end
    
  # Methods to be called from inside module.
    
  # Add all model specific observers.
  # Called when opening or creating a model.
  def self.add_observers(model)
  
    model.add_observer(MyModelObserver.new)
    model.selection.add_observer(MySelectionObserver.new)
    
  end

  # Check if Building Group or Template ComponentInstance is being entered.
  # Called wen changing active drawing context.
  def self.check_if_entering(model)
  
    path_size = (model.active_path || []).size
    # Model.active_path Returns nil, not empty array, when in model root -_-.

    if Observers.previous_path_size < path_size
      # A group/component was entered.

      e = model.active_path.last
      if Building.group_is_building?(e)
        # Entered group/component represents a building.
        unless Building.onGroupEnter
          Observers.disable
          model.close_active
          Observers.enable
          path_size -= 1
        end
      elsif Template.component_is_template?(e)
        # Entered group/component is an instance of a Template definition.
        TemplateEditor.onComponentEnter
      end

    end
    
    Observers.previous_path_size = path_size
      
  end
  
  # Observer classes.
  
  # App observer adding model specific observers on all models.
  class MyAppObserver < Sketchup::AppObserver

    def onOpenModel(model)
      return if Observers.disabled?
      Observers.add_observers model
    end

    def onNewModel(model)
      return if Observers.disabled?
      Observers.add_observers model
    end

    # Call onOpenModel or onNewModel on startup.
    def expectsStartupModelNotifications
      true
    end

  end

  # Model observer checking if a Building Group or Template ComponentDefinition
  # is entered. Also updates template and part info dialog when drawing context
  # changes or when undoing and redoing.
  # Also saves data in part and template info dialogs to model before model is
  # saved to disk.
  # Also attach template data to template component instance when placed from
  # component browser.
  class MyModelObserver < Sketchup::ModelObserver

    def onActivePathChanged(model)
      return if Observers.disabled?
      Observers.check_if_entering model
      TemplateEditor.onActivePathChanged
    end
    
    def onPlaceComponent(instance)
      return if Observers.disabled?
      TemplateEditor.onPlaceComponent instance
    end
    
    def onPreSaveModel(*)
      return if Observers.disabled?
      TemplateEditor.onPreSaveModel
    end
    
    def onTransactionRedo(*)
      return if Observers.disabled?
      TemplateEditor.onUndoRedo
    end
    
    def onTransactionUndo(*)
      return if Observers.disabled?
      TemplateEditor.onUndoRedo
    end

  end

  # Selection observer updating template and part info dialog when opened.
  class MySelectionObserver < Sketchup::SelectionObserver

    # Called on all selection changes EXCEPT when selection is completely
    # emptied...
    def onSelectionBulkChange(*)
      return if Observers.disabled?
      TemplateEditor.onSelectionChange
    end

    # ...in which case this is called instead.
    def onSelectionCleared(*)
      return if Observers.disabled?
      TemplateEditor.onSelectionChange
    end

  end# Class

  # Attach app observer if not already attached.
  @@app_observer ||= nil
  unless @@app_observer
    @@app_observer = MyAppObserver.new
    Sketchup.add_observer @@app_observer
  end

end

end