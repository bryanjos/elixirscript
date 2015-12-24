defmodule ElixirScript.Translator.Function do
  @moduledoc false
  alias ESTree.Tools.Builder, as: JS
  alias ElixirScript.Translator
  alias ElixirScript.Translator.Utils
  alias ElixirScript.PatternMatching.Match

  @patterns JS.member_expression(
    JS.member_expression(
      JS.identifier("Elixir"),
      JS.identifier("Core")
    ),
    JS.identifier("Patterns")
  )

  def process_function(name, functions, env) do
    { result, _ } = make_anonymous_function(functions, env, name)

    declarator = JS.variable_declarator(
      JS.identifier(name),
      result
    )

    { JS.variable_declaration([declarator], :const), env }
  end

  def make_anonymous_function(functions, env, name \\ nil) do
    clauses = functions
    |> Enum.map(fn
      {:->, _, [ [{:when, _, [params | guards]}], body ]} ->
        process_function_body(params, body, env, name, guards)
      ({:->, _, [params, body]}) ->
        process_function_body(params, body, env, name)

      ({_, _, [{:when, _, [{_, _, params} | guards] }, [do: body]]}) ->
        process_function_body(params, body, env, name, guards)

      ({_, _, [{_, _, params}, [do: body]]}) ->
        process_function_body(params, body, env, name)

      ({_, _, [{_, _, params}]}) ->
        process_function_body(params, [], env, name)
    end)

    { make_defmatch(clauses), env }
  end

  def make_defmatch(clauses) do
    JS.call_expression(
      JS.member_expression(
        @patterns,
        JS.identifier("defmatch")
      ),
      clauses
    )
  end

  defp process_function_body(params, body, env, name, guards \\ nil) do
    env = ElixirScript.Env.function_env(env, {name, get_arity(params)})

    { patterns, params, env } = process_params(params, env)
    { body, _ } = make_function_body(body, env)

    if guards do
      { guard_body, _ } = hd(List.wrap(guards))
      |> prepare_function_body(env)

      guard_body = JS.block_statement(guard_body)
      make_function_clause(patterns, params, body, guard_body)
    else
      make_function_clause(patterns, params, body, nil)
    end
  end

  def wrap_params(params) when is_atom(params), do: []
  def wrap_params(params), do: List.wrap(params)

  def make_function_body(body, env) do
    { body, _ } = body
    |> prepare_function_body(env)


    { JS.block_statement(body), env }
  end

  defp get_arity(params) when is_atom(params), do: 0
  defp get_arity(params) when is_tuple(params), do: 1
  defp get_arity(params), do: length(params)

  defp make_params(params) do
    Enum.filter(params, fn
      (%ESTree.Identifier{name: :undefined}) -> false
      (_) -> true
    end)
  end

  defp process_params(params, env) do
    params = wrap_params(params)
    { patterns, params, env } = Match.process_match(params, env)
    { patterns, make_params(params), env }
  end

  def make_function_clause(patterns, params, body, guard_body) do
    arguments = [
            JS.array_expression(patterns),
            JS.function_expression(params, [], body),
          ]

    if guard_body do
      arguments = arguments ++ [JS.function_expression(params, [], guard_body)]
    end

    JS.call_expression(
      JS.member_expression(
        @patterns,
        JS.identifier("make_case")
      ),
      arguments
    )
  end

  def make_function_or_property_call(module_name, function_name, env) do
    the_name = get_module_name_for_function(module_name, env)

    js_ast = JS.call_expression(
      JS.member_expression(
        JS.member_expression(
          JS.identifier("Elixir"),
          JS.identifier("Core")
        ),
        JS.identifier("call_property")
      ),
      [
        Utils.make_module_expression_tree(the_name, false, env),
        Translator.translate!(to_string(function_name), env)
      ]
    )

    { js_ast, env }
  end

  defp get_module_name_for_function(module_name, env) do
    case module_name do
      {:__aliases__, _, name} ->
        module_name = ElixirScript.Module.quoted_to_name(name)
        get_js_name(module_name, env)
      {name, _, _} when is_atom(name) ->
        get_js_name(name, env)
      {{:., _, [_, _]}, _, _ } = ast ->
        ast
      {{:., _, [{:__aliases__, _, _}]}, _, _} = ast ->
        ast
      name ->
        get_js_name(name, env)
    end
  end

  def make_function_call(function_name, params, env) when is_tuple(function_name) do
    { Utils.make_call_expression(function_name, params, env), env }
  end

  def make_function_call(function_name, params, env) do
    { Utils.make_call_expression(Utils.filter_name(function_name), params, env), env }
  end

  def make_function_call(module_name, function_name, params, env) do
    the_name = get_module_name_for_function(module_name, env)
    { Utils.make_call_expression(the_name, Utils.filter_name(function_name), params, env), env }
  end

  def prepare_function_body(body, env) do
    { list, env } = case body do
      nil ->
        { [], env }
      list when is_list(list) ->
        Enum.map_reduce(list, env, fn(x, env) ->
          Translator.translate(x, env)
        end)
      {:__block__, _, list} ->
        Enum.map_reduce(list, env, fn(x, env) ->
          Translator.translate(x, env)
        end)
      _ ->
        Enum.map_reduce(List.wrap(body), env, fn(x, env) ->
          Translator.translate(x, env)
        end)
    end

    list = Utils.inflate_groups(list)
    |> return_last_expression

    { list, env }
  end

  def return_last_expression(nil) do
    nil
  end

  def return_last_expression([]) do
    [JS.return_statement(JS.literal(nil))]
  end

  def return_last_expression(%ESTree.BlockStatement{} = block) do
    %ESTree.BlockStatement{ block | body: return_last_expression(block.body) }
  end

  def return_last_expression(list) when is_list(list) do
    last_item = List.last(list)

    last_item = case last_item do
      %ESTree.Literal{} ->
        JS.return_statement(last_item)
      %ESTree.Identifier{} ->
        JS.return_statement(last_item)
      %ESTree.VariableDeclaration{} ->
        declaration = hd(last_item.declarations).id

        return_statement = case declaration do
          %ESTree.ArrayPattern{elements: elements} ->
            if(length(elements) == 1) do
              JS.return_statement(hd(declaration.elements))
            else
              JS.return_statement(JS.array_expression(declaration.elements))
            end
          _ ->
            JS.return_statement(declaration)
        end

        [last_item, return_statement]
      %ESTree.BlockStatement{} ->
        last_item = %ESTree.BlockStatement{ last_item | body: return_last_expression(last_item.body) }
      _ ->
        if String.contains?(last_item.type, "Expression") do
          JS.return_statement(last_item)
        else
          [last_item, JS.return_statement(JS.literal(nil))]
        end
    end


    list = Enum.take(list, length(list)-1)
    |> Enum.map(fn(x) ->
      case x do
        %ESTree.MemberExpression{} ->
          JS.expression_statement(x)
        %ESTree.CallExpression{} ->
          JS.expression_statement(x)
        _ ->
          x
      end
    end)

    if is_list(last_item) do
      list ++ last_item
    else
      list ++ [last_item]
    end
  end

  defp get_js_name([Elixir | _] = list, _) do
    list
  end

  defp get_js_name(module_name, env) when is_list(module_name) do
    ElixirScript.Module.quoted_to_name({:__aliases__, [], module_name})
    |> get_js_name(env)
  end

  defp get_js_name(module_name, env) do

    cond do
      module_name in env.requires ->
        ElixirScript.Module.name_to_js_name(module_name)

      module_name in ElixirScript.State.list_module_names ->
        ElixirScript.State.add_module_reference(env.module, module_name)
        ElixirScript.Module.name_to_js_name(module_name)

      true ->
        case Atom.to_string(module_name) do
          "Elixir." <> _ ->
            {:__aliases__, _, name } = ElixirScript.Module.name_to_quoted(module_name)
            name
          _ ->
            module_name
        end
    end
  end
end
