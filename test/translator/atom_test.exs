defmodule ElixirScript.Translator.Atom.Test do
  use ShouldI
  import ElixirScript.TestHelper

  should "translate atom" do
    ex_ast = quote do: :atom
    assert_translation(ex_ast, "Elixir.Kernel.SpecialForms.atom('atom')")
  end

  should "Call Atom module" do
    ex_ast = quote do: Atom.to_string(:atom)
    assert_translation(ex_ast, "Elixir$ElixirScript$Atom.to_string(Elixir.Kernel.SpecialForms.atom('atom'))")
  end
end
