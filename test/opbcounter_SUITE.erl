%% -------------------------------------------------------------------
%%
%% Copyright (c) 2014 SyncFree Consortium.  All Rights Reserved.
%%
% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------
-module(opbcounter_SUITE).

-compile({parse_transform, lager_transform}).

%% common_test callbacks
-export([init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2,
         all/0]).

%% tests
-export([new_bcounter_test/1,
          increment_test/1,
          decrement_test/1,
          transfer_test/1,
          conditional_write_test/1]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").
-include_lib("kernel/include/inet.hrl").

init_per_suite(Config) ->
    test_utils:at_init_testsuite(),
    Clusters = test_utils:set_up_clusters_common(Config),
    Nodes = hd(Clusters),
    [{nodes, Nodes}|Config].

end_per_suite(Config) ->
    Config.

init_per_testcase(_Case, Config) ->
    Config.

end_per_testcase(_, _) ->
    ok.

all() -> [new_bcounter_test,
          increment_test,
          decrement_test,
          transfer_test,
          conditional_write_test].


%% Tests creating a new `bcounter()'.
new_bcounter_test(Config) ->
    Nodes = proplists:get_value(nodes, Config),
    FirstNode = hd(Nodes),
    lager:info("new_bcounter_test started"),
    Type = antidote_crdt_bcounter,
    Key = bcounter1,
    %% Test reading a new key of type `antidote_crdt_bcounter' creates a new `bcounter()'.
    Result0 = rpc:call(FirstNode, antidote, read,
                        [Key, Type]),
    Counter0 = antidote_crdt_bcounter:new(),
    ?assertEqual({ok, Counter0}, Result0).

%% Tests incrementing a `bcounter()'.
increment_test(Config) ->
    Nodes = proplists:get_value(nodes, Config),
    FirstNode = hd(Nodes),
    lager:info("increment_test started"),
    Type = antidote_crdt_bcounter,
    Key = bcounter2,
    %% Test simple read and write operations.
    Result0 = rpc:call(FirstNode, antidote, append,
        [Key, Type, {increment, {10, r1}}]),
    ?assertMatch({ok, _}, Result0),
    Result1 = rpc:call(FirstNode, antidote, read, [Key, Type]),
    {ok, Counter1} = Result1,
    ?assertEqual(10, antidote_crdt_bcounter:permissions(Counter1)),
    ?assertEqual(10, antidote_crdt_bcounter:localPermissions(r1,Counter1)),
    ?assertEqual(0, antidote_crdt_bcounter:localPermissions(r2,Counter1)),
    %% Test bulk transaction with read and write operations.
    Result2 = rpc:call(FirstNode, antidote, clocksi_execute_int_tx,
        [[{update, {Key, Type, {increment, {7, r1}}}}, {update, {Key, Type, {increment, {5, r2}}}}, {read, {Key, Type}}]]),
    ?assertMatch({ok, _}, Result2),
    {ok, {_, [Counter2], _}} = Result2,
    ?assertEqual(22, antidote_crdt_bcounter:permissions(Counter2)),
    ?assertEqual(17, antidote_crdt_bcounter:localPermissions(r1,Counter2)),
    ?assertEqual(5, antidote_crdt_bcounter:localPermissions(r2,Counter2)).

%% Tests decrementing a `bcounter()'.
decrement_test(Config) ->
    Nodes = proplists:get_value(nodes, Config),
    FirstNode = hd(Nodes),
    lager:info("decrement_test started"),
    Type = antidote_crdt_bcounter,
    Key = bcounter3,
    %% Test an allowed chain of operations.
    Result0 = rpc:call(FirstNode, antidote, clocksi_execute_int_tx,
        [[{update, {Key, Type, {increment, {7, r1}}}}, {update, {Key, Type, {increment, {5, r2}}}},
            {update, {Key, Type, {decrement, {3, r2}}}}, {update, {Key, Type, {decrement, {2, r1}}}},
            {read, {Key, Type}}]]),
    ?assertMatch({ok, _}, Result0),
    {ok, {_, [Counter0], _}} = Result0,
    ?assertEqual(7, antidote_crdt_bcounter:permissions(Counter0)),
    ?assertEqual(5, antidote_crdt_bcounter:localPermissions(r1,Counter0)),
    ?assertEqual(2, antidote_crdt_bcounter:localPermissions(r2,Counter0)),
    %% Test a forbidden chain of operations.
    Result1 = rpc:call(FirstNode, antidote, clocksi_execute_int_tx,
        [[{update, {Key, Type, {decrement, {3, r2}}}}, {read, {Key, Type}}]]),
    ?assertEqual({error, no_permissions}, Result1).

%% Tests transferring permissions between replicas in a `bcounter()'.
transfer_test(Config) ->
    Nodes = proplists:get_value(nodes, Config),
    FirstNode = hd(Nodes),
    lager:info("transfer_test started"),
    Type = antidote_crdt_bcounter,
    Key = bcounter4,
    %% Initialize the `bcounter()' with some increment and decrement operations.
    Result0 = rpc:call(FirstNode, antidote, clocksi_execute_int_tx,
        [[{update, {Key, Type, {increment, {7, r1}}}}, {update, {Key, Type, {increment, {5, r2}}}},
        {update, {Key, Type, {decrement, {3, r2}}}}, {read, {Key, Type}}]]),
    ?assertMatch({ok, _}, Result0),
    {ok, {_, [Counter0], _}} = Result0,
    ?assertEqual(9, antidote_crdt_bcounter:permissions(Counter0)),
    ?assertEqual(7, antidote_crdt_bcounter:localPermissions(r1,Counter0)),
    ?assertEqual(2, antidote_crdt_bcounter:localPermissions(r2,Counter0)),
    %% Test a forbidden transference.
    Result1 = rpc:call(FirstNode, antidote, append,
        [Key, Type, {transfer, {3, r1, r2}}]),
    ?assertEqual({error, no_permissions}, Result1),
    %% Test transfered permissions enable the previous operation.
    Result2 = rpc:call(FirstNode, antidote, clocksi_execute_int_tx,
        [[{update, {Key, Type, {transfer, {2, r2, r1}}}},
        {update, {Key, Type, {transfer, {3, r1, r2}}}}, {read, {Key, Type}}]]),
    ?assertMatch({ok, _}, Result2),
    {ok, {_, [Counter1], _}} = Result2,
    ?assertEqual(9, antidote_crdt_bcounter:permissions(Counter1)),
    ?assertEqual(8, antidote_crdt_bcounter:localPermissions(r1,Counter1)),
    ?assertEqual(1, antidote_crdt_bcounter:localPermissions(r2,Counter1)).

%% Tests the conditional write mechanism required for `generate_downstream()' and `update()' to be atomic.
%% Such atomic execution is required for the correctness of `bcounter()' CRDT.
conditional_write_test(Config) ->
    Nodes = proplists:get_value(nodes, Config),
    case rpc:call(hd(Nodes), application, get_env, [antidote, txn_cert]) of
        {ok, true} ->
            conditional_write_test_run(Nodes);
        _ ->
            pass
    end.

conditional_write_test_run(Nodes) ->
    FirstNode = hd(Nodes),
    LastNode = lists:last(Nodes),
    Type = antidote_crdt_bcounter,
    Key = bcounter5,

    {ok, {_,_,AfterIncrement}} = rpc:call(FirstNode, antidote, append,
        [Key, Type, {increment, {10, r1}}]),


    %% Start a transaction on the first node and perform a read operation.
    {ok, TxId1} = rpc:call(FirstNode, antidote, clocksi_istart_tx, [AfterIncrement]),
    {ok, _} = rpc:call(FirstNode, antidote, clocksi_iread, [TxId1, Key, Type]),
    %% Execute a transaction on the last node which performs a write operation.
    {ok, TxId2} = rpc:call(LastNode, antidote, clocksi_istart_tx, [AfterIncrement]),
    ok = rpc:call(LastNode, antidote, clocksi_iupdate,
             [TxId2, Key, Type, {decrement, {3, r1}}]),
    CommitTime1 = rpc:call(LastNode, antidote, clocksi_iprepare, [TxId2]),
    ?assertMatch({ok, _}, CommitTime1),
    End1 = rpc:call(LastNode, antidote, clocksi_icommit, [TxId2]),
    ?assertMatch({ok, _}, End1),
    {ok, {_,AfterTxn2}} = End1,
    %% Resume the first transaction and check that it fails.
    Result0 = rpc:call(FirstNode, antidote, clocksi_iupdate,
         [TxId1, Key, Type, {decrement, {3, r1}}]),
    ?assertEqual(ok, Result0),
    CommitTime2 = rpc:call(FirstNode, antidote, clocksi_iprepare, [TxId1]),
    ?assertEqual({aborted, TxId1}, CommitTime2),
    %% Test that the failed transaction didn't affect the `bcounter()'.
    Result1 = rpc:call(FirstNode, antidote, clocksi_read, [AfterTxn2, Key, Type]),
    {ok, {_, [Counter1], _}} = Result1,
    ?assertEqual(7, antidote_crdt_bcounter:permissions(Counter1)).