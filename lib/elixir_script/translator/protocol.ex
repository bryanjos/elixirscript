defmodule ElixirScript.Translator.Protocol do
  @moduledoc false

  alias ESTree.Tools.Builder, as: JS
  alias ElixirScript.Translator
  alias ElixirScript.Translator.Module
  alias ElixirScript.Translator.JSModule
  alias ElixirScript.Translator.Map
  alias ElixirScript.Translator.Function
  alias ElixirScript.Translator.Utils

  @doc """
  Takes a list of protocols and turns them into modules
  """
  def consolidate(protocols, env) when is_list(protocols) do
    Enum.map(protocols, fn(protocol) ->
      do_consolidate(protocol, env)
    end)
  end

  defp do_consolidate(protocol, env) do
    name = protocol.name
    spec = protocol.spec
    impls = protocol.impls |> Dict.to_list

    {spec_imports, spec_body, spec} = define_spec(name, spec, env)
    {impl_imports, impl_body, impls} = define_impls(name, impls, env)

    body = spec_body ++ impl_body
    imports = spec_imports ++ impl_imports

    create_module(name, spec, impls, imports, body, env)
  end

  defp define_spec(name, spec, env) do
    { body, functions } = extract_function_from_spec(spec)

    { exported_functions, _ } = process_functions(functions, env)

    body = Module.translate_body(body, env)
    modules_refs = ElixirScript.State.get_module_references(name)

    {imports, body} = Module.extract_imports_from_body(body)

    imports = Module.process_imports(imports, modules_refs)
    imports = imports.imports

    object = Enum.map(exported_functions, fn({key, value}) ->
      Map.make_property(JS.identifier(Utils.filter_name(key)), value)
    end)
    |> JS.object_expression

    declarator = JS.variable_declarator(
      JS.identifier(ElixirScript.Module.name_to_js_name(name)),
      JS.call_expression(
        JS.member_expression(
          JS.identifier(:Elixir),
          JS.member_expression(
            JS.identifier(:Kernel),
            JS.identifier(:defprotocol)
          )
        ),
        [object]
      )
    )

    {imports, body, [JS.variable_declaration([declarator], :let)]}
  end

  defp define_impls(_, [], _) do
    { [], [], [] }
  end

  defp define_impls(name, impls, env) do
    Enum.map(impls, fn({type, impl}) ->
      type = map_to_js(type)
      { body, functions } = Module.extract_functions_from_module(impl)
      { exported_functions, _ } = process_functions(functions, env)

      body = Module.translate_body(body, env)
      modules_refs = ElixirScript.State.get_module_references(name)

      {imports, body} = Module.extract_imports_from_body(body)

      imports = Module.process_imports(imports, modules_refs)
      imports = imports.imports

      object = Enum.map(exported_functions, fn({key, value}) ->
        Map.make_property(JS.identifier(Utils.filter_name(key)), value)
      end)
      |> JS.object_expression

      impl = JS.call_expression(
        JS.member_expression(
          JS.identifier(:Elixir),
          JS.member_expression(
            JS.identifier(:Kernel),
            JS.identifier(:defimpl)
          )
        ),
        [JS.identifier(ElixirScript.Module.name_to_js_name(name)), type, object]
      )

      {imports, body, [impl]}

    end)
    |> Enum.reduce({[], [], []}, fn({impl_imports, impl_body, impl}, acc) ->
      {
        elem(acc, 0) ++ impl_imports,
        elem(acc, 1) ++ impl_body,
        elem(acc, 2) ++ impl
      }
    end)
  end

  def make_standard_lib_impl(protocol, type, impl, env) do
    type = map_to_js(type)
    protocol = Translator.translate(protocol, env)

    { _, functions } = Module.extract_functions_from_module(impl)
    { exported_functions, _ } = process_functions(functions, env)

    object = Enum.map(exported_functions, fn({key, value}) ->
      Map.make_property(JS.identifier(Utils.filter_name(key)), value)
    end)
    |> JS.object_expression

    JS.call_expression(
      JS.member_expression(
        JS.identifier(:Elixir),
        JS.member_expression(
          JS.identifier(:Kernel),
          JS.identifier(:defimpl)
        )
      ),
      [protocol, type, object]
    )
  end

  defp create_module(name, spec, impls, imports, body, _) do
    default = JS.export_default_declaration(JS.identifier(ElixirScript.Module.name_to_js_name(name)))

    %JSModule{
      name: name,
      body: imports ++ body ++ spec ++ impls ++ [default]
    }
  end

  defp extract_function_from_spec({:__block__, meta, body_list}) do
    { body_list, functions } = Enum.map_reduce(body_list,
      %{exported: HashDict.new(), private: HashDict.new()}, fn
        ({:def, _, [{name, _, _}]} = function, state) ->
          {
            nil,
            %{ state | exported: HashDict.put(state.exported, name, HashDict.get(state.exported, name, []) ++ [function]) }
          }
        (x, state) ->
          { x, state }
      end)

    body_list = Enum.filter(body_list, fn(x) -> !is_nil(x) end)
    body = {:__block__, meta, body_list}

    { body, functions }
  end

  defp process_functions(%{ exported: exported, private: private }, env) do
    exported_functions = Enum.map(Dict.keys(exported), fn(key) ->
      functions = Dict.get(exported, key)
      { key, Function.make_anonymous_function(functions, env) }
    end)

    private_functions = Enum.map(Dict.keys(private), fn(key) ->
      functions = Dict.get(private, key)
      { key, Function.make_anonymous_function(functions, env) }
    end)

    { exported_functions, private_functions }
  end

  defp map_to_js({:__aliases__, _, [:Integer]}) do
    JS.member_expression(
      JS.member_expression(
        JS.identifier(:Elixir),
        JS.identifier(:Core)
      ),
      JS.identifier(:Integer)
    )
  end

  defp map_to_js({:__aliases__, _, [:Tuple]}) do
    JS.member_expression(
      JS.member_expression(
        JS.identifier(:Elixir),
        JS.identifier(:Core)
      ),
      JS.identifier(:Tuple)
    )
  end

  defp map_to_js({:__aliases__, _, [:Atom]}) do
    JS.identifier(:Symbol)
  end

  defp map_to_js({:__aliases__, _, [:List]}) do
    JS.identifier(:Array)
  end

  defp map_to_js({:__aliases__, _, [:BitString]}) do
    JS.member_expression(
      JS.member_expression(
        JS.identifier(:Elixir),
        JS.identifier(:Core)
      ),
      JS.identifier(:BitString)
    )
  end

  defp map_to_js({:__aliases__, _, [:Float]}) do
    JS.member_expression(
      JS.member_expression(
        JS.identifier(:Elixir),
        JS.identifier(:Core)
      ),
      JS.identifier(:Float)
    )
  end

  defp map_to_js({:__aliases__, _, [:Function]}) do
    JS.identifier(:Function)
  end

  defp map_to_js({:__aliases__, _, [:PID]}) do
    JS.member_expression(
      JS.member_expression(
        JS.identifier(:Elixir),
        JS.identifier(:Core)
      ),
      JS.identifier(:PID)
    )
  end

  defp map_to_js({:__aliases__, _, [:Port]}) do
    JS.member_expression(
      JS.identifier(:Elixir),
      JS.identifier(:Port)
    )
  end

  defp map_to_js({:__aliases__, _, [:Reference]}) do
    JS.member_expression(
      JS.identifier(:Elixir),
      JS.identifier(:Reference)
    )
  end

  defp map_to_js({:__aliases__, _, [:Map]}) do
    JS.identifier(:Object)
  end

  defp map_to_js({:__aliases__, _, [:Any]}) do
    quoted = quote do
      nil
    end

    Translator.translate(quoted, ElixirScript.State.get().env)
  end


  defp map_to_js({:__aliases__, _, module}) do
    ElixirScript.Translator.Struct.get_struct_class(
      module,
      ElixirScript.State.get().env
    )
  end

end
