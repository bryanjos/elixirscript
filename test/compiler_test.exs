defmodule ElixirScript.Compiler.Test do
  use ExUnit.Case

  test "Can compile one entry module" do
    result = ElixirScript.Compiler.compile(Version)
    assert is_binary(result)
  end

  test "Can compile multiple entry modules" do
    result = ElixirScript.Compiler.compile([Atom, String, Agent])
    assert is_binary(result)
  end

  test "Error on unknown module" do
    assert_raise ElixirScript.CompileError, fn ->
      ElixirScript.Compiler.compile(SomeModule)
    end
  end

  test "Output" do
    result = ElixirScript.Compiler.compile(Atom, [])
    assert result =~ "export default Elixir"
  end

  test "Output file with default name" do
    path = System.tmp_dir()

    ElixirScript.Compiler.compile(Atom, [output: path])
    assert File.exists?(Path.join([path, "Elixir.App.js"]))
  end

  test "Output file with custom name" do
    path = System.tmp_dir()
    path = Path.join([path, "myfile.js"])

    ElixirScript.Compiler.compile(Atom, [output: path])
    assert File.exists?(path)
  end
end
