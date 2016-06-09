module TestModule

  def test()
    p "test"
  end
  
end

class TestClass

  include TestModule
  
  def test()
    super
  end

end