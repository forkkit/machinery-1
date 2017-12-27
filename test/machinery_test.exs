defmodule MachineryTest do
  use ExUnit.Case
  doctest Machinery

  alias MachineryTest.TestStruct
  alias MachineryTest.TestStateMachine
  alias MachineryTest.TestStateMachineWithGuard

  defmodule TestStruct do
    defstruct state: nil, missing_fields: nil, force_exception: false
  end

  defmodule TestStateMachineWithGuard do
    use Machinery,
      states: ["created", "partial", "completed"],
      transitions: %{
        "created" => ["partial", "completed"],
        "partial" => "completed"
      }

    def guard_transition(struct, "completed") do
      # Code to simulate and force an exception inside a
      # guard function.
      if Map.get(struct, :force_exception) do
        Machinery.non_existing_function_should_raise_error()
      end

      Map.get(struct, :missing_fields) == false
    end
  end

  defmodule TestStateMachine do
    use Machinery,
      states: ["created", "partial", "completed"],
      transitions: %{
        "created" => ["partial", "completed"],
        "partial" => "completed"
      }

    def before_transition(struct, "partial") do
      # Code to simulate and force an exception inside a
      # guard function.
      if Map.get(struct, :force_exception) do
        Machinery.non_existing_function_should_raise_error()
      end

      Map.put(struct, :missing_fields, true)
    end

    def after_transition(struct, "completed") do
      Map.put(struct, :missing_fields, false)
    end

    def persist(struct, next_state) do
      # Code to simulate and force an exception inside a
      # guard function.
      if Map.get(struct, :force_exception) do
        Machinery.non_existing_function_should_raise_error()
      end

      Map.put(struct, :state, next_state)
    end
  end

  test "All internal functions should be injected into AST" do
    assert :erlang.function_exported(TestStateMachine, :_machinery_initial_state, 0)
    assert :erlang.function_exported(TestStateMachine, :_machinery_states, 0)
    assert :erlang.function_exported(TestStateMachine, :_machinery_transitions, 0)
  end

  test "Only the declared transitions should be valid" do
    created_struct = %TestStruct{state: "created", missing_fields: false}
    partial_struct = %TestStruct{state: "partial", missing_fields: false}
    stateless_struct = %TestStruct{}
    completed_struct = %TestStruct{state: "completed"}

    assert {:ok, %TestStruct{state: "partial"}} = Machinery.transition_to(created_struct, TestStateMachine, "partial")
    assert {:ok, %TestStruct{state: "completed", missing_fields: false}} = Machinery.transition_to(created_struct, TestStateMachine, "completed")
    assert {:ok, %TestStruct{state: "completed", missing_fields: false}} = Machinery.transition_to(partial_struct, TestStateMachine, "completed")
    assert {:error, "Transition to this state isn't declared."} = Machinery.transition_to(stateless_struct, TestStateMachine, "created")
    assert {:error, "Transition to this state isn't declared."} = Machinery.transition_to(completed_struct, TestStateMachine, "created")
  end

  test "Guard functions should be executed before moving the resource to the next state" do
    struct = %TestStruct{state: "created", missing_fields: true}
    assert {:error, "Transition not completed, blocked by guard function."} = Machinery.transition_to(struct, TestStateMachineWithGuard, "completed")
  end

  test "Guard functions should allow or block transitions" do
    allowed_struct = %TestStruct{state: "created", missing_fields: false}
    blocked_struct = %TestStruct{state: "created", missing_fields: true}

    assert {:ok, %TestStruct{state: "completed", missing_fields: false}} = Machinery.transition_to(allowed_struct, TestStateMachineWithGuard, "completed")
    assert {:error, "Transition not completed, blocked by guard function."} = Machinery.transition_to(blocked_struct, TestStateMachineWithGuard, "completed")
  end

  test "The first declared state should be considered the initial one" do
    stateless_struct = %TestStruct{}
    assert {:ok, %TestStruct{state: "partial"}} = Machinery.transition_to(stateless_struct, TestStateMachine, "partial")
  end

  test "Modules without guard conditions should allow transitions by default" do
    struct = %TestStruct{state: "created"}
    assert {:ok, %TestStruct{state: "completed"}} = Machinery.transition_to(struct, TestStateMachine, "completed")
  end

  @tag :capture_log
  test "Implict rescue on the guard clause internals should raise any other excepetion not strictly related to missing guard_tranistion/2 existence" do
    wrong_struct = %TestStruct{state: "created", force_exception: true}
    assert_raise UndefinedFunctionError, fn() ->
      Machinery.transition_to(wrong_struct, TestStateMachineWithGuard, "completed")
    end
  end

  test "after_transition/2 and before_transition/2 callbacks should be automatically executed" do
    struct = %TestStruct{}
    assert struct.missing_fields == nil

    {:ok, partial_struct} = Machinery.transition_to(struct, TestStateMachine, "partial")
    assert partial_struct.missing_fields == true

    {:ok, completed_struct} = Machinery.transition_to(struct, TestStateMachine, "completed")
    assert completed_struct.missing_fields == false
  end

  @tag :capture_log
  test "Implict rescue on the callbacks internals should raise any other excepetion not strictly related to missing callbacks_fallback/2 existence" do
    wrong_struct = %TestStruct{state: "created", force_exception: true}
    assert_raise UndefinedFunctionError, fn() ->
      Machinery.transition_to(wrong_struct, TestStateMachine, "partial")
    end
  end

  test "Persist function should be called after the transition" do
    struct = %TestStruct{state: "partial"}
    assert {:ok, _} = Machinery.transition_to(struct, TestStateMachine, "completed")
  end

  @tag :capture_log
  test "Persist function should still reaise errors if not related to the existence of persist/1 method" do
    wrong_struct = %TestStruct{state: "created", force_exception: true}
    assert_raise UndefinedFunctionError, fn() ->
      Machinery.transition_to(wrong_struct, TestStateMachine, "completed")
    end
  end
end
