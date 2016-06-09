class ParentClass

  @@parent_var = "parent_var"
  
  PARENT_COSNTANT = "Parent constant"
  OVERRIDDEN = false
  
  def read_child_constant
    CHILD_CONSTANT
  end

end

class ChildClass < ParentClass

  CHILD_CONSTANT = "Child constant"
  OVERRIDDEN = true

  def read_constant
    PARENT_COSNTANT
  end
  
end