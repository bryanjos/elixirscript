defmodule ElixirScript.Translate.Forms.JS do
  @moduledoc false
  alias ESTree.Tools.Builder, as: J
  alias ElixirScript.Translate.Helpers
  alias ElixirScript.Translate.Form

  def call_property() do
    J.member_expression(
      Helpers.functions(),
      J.identifier("call_property")
    )
  end

  def compile({{:., _, [ElixirScript.JS, :debugger]}, _, _}, state) do
    ast = J.debugger_statement()
    {ast, state}
  end

  def compile({{:., _, [ElixirScript.JS, :this]}, _, _}, state) do
    ast = J.this_expression()
    {ast, state}
  end

  def compile({{:., _, [ElixirScript.JS, :new]}, _, [module, params]}, state) do
    members = Module.split(module)

    members = case members do
      ["JS" | rest] ->
        rest
      x ->
        x
    end

    params = case params do
      p when is_list(p) ->
        Enum.map(params, &Form.compile!(&1, state))
      _ ->
        [J.rest_element(Form.compile!(params, state))]
    end

    ast = Helpers.new(
      ElixirScript.Translate.Identifier.make_namespace_members(members),
      params
    )

    {ast, state}
  end

  def compile({{:., _, [ElixirScript.JS, :throw]}, _, [term]}, state) do
    ast = J.throw_statement(
      Form.compile!(term, state)
    )

    {ast, state}
  end

  def compile({{:., _, [ElixirScript.JS, :import]}, _, [term]}, state) do
    ast = Helpers.call(
      J.identifier("import"),
      [Form.compile!(term, state)]
    )

    {ast, state}
  end

  def compile({{:., _, [ElixirScript.JS, :mutate]}, _, [object, map]}, state) do
    ast = Helpers.call(
      J.member_expression(
        J.identifier("Object"),
        J.identifier("assign")
      ),
      [
        Form.compile!(object, state),
        Form.compile!(map, state)
      ]
    )

    {ast, state}
  end

  def compile({{:., _, [ElixirScript.JS, :mutate]}, _, [object, key, value]}, state) do
    ast = Helpers.assign(
      J.member_expression(
        Form.compile!(object, state),
        Form.compile!(key, state),
        true
      ),
      Form.compile!(value, state)
    )

    {ast, state}
  end

  def compile({{:., _, [ElixirScript.JS, :map_to_object]}, _, [object]}, state) do
    ast = Helpers.call(
      J.member_expression(
        Helpers.functions(),
        J.identifier("map_to_object")
      ),
      [
        Form.compile!(object, state)
      ]
    )

    {ast, state}
  end

  def compile({{:., _, [ElixirScript.JS, :map_to_valid_object]}, _, [object]}, state) do
    ast = Helpers.call(
      J.member_expression(
        Helpers.functions(),
        J.identifier("map_to_valid_object")
      ),
      [
        Form.compile!(object, state)
      ]
    )

    {ast, state}
  end

  def compile({{:., _, [ElixirScript.JS, :symbol_to_string]}, _, [symbol]}, state) do
    ast = Helpers.call(
      J.member_expression(
        Helpers.functions(),
        J.identifier("symbol_to_string")
      ),
      [
        Form.compile!(symbol, state)
      ]
    )

    {ast, state}
  end
end
