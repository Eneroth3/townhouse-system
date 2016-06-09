module TestModule

  def test()
    p "test"
    @var = "var"
  end
  
end

class TestClass

  include TestModule
  
  def test()
    super
    puts @var
  end

end