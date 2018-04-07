module ParserTests exposing (all)

import Cli.UsageSpec exposing (UsageSpec)
import Command
import Expect exposing (Expectation)
import Test exposing (..)


flagsAndOperands : List UsageSpec -> List String -> { flags : List ParsedOption, operands : List String }
flagsAndOperands usageSpecs argv =
    flagsAndOperands_ usageSpecs argv { flags = [], operands = [] }


flagsAndOperands_ :
    List UsageSpec
    -> List String
    -> { flags : List ParsedOption, operands : List String }
    -> { flags : List ParsedOption, operands : List String }
flagsAndOperands_ usageSpecs argv soFar =
    case argv of
        [] ->
            soFar

        first :: rest ->
            case String.toList first of
                '-' :: '-' :: restOfFirstString ->
                    flagsAndOperands_ usageSpecs
                        rest
                        { flags = soFar.flags ++ [ Flag first ]
                        , operands = soFar.operands
                        }

                _ ->
                    flagsAndOperands_ usageSpecs
                        rest
                        { flags = soFar.flags
                        , operands = soFar.operands ++ [ first ]
                        }


type ParsedOption
    = Flag String
    | Option String String


all : Test
all =
    describe "flags and operands extraction"
        [ test "recognizes empty operands and flags" <|
            \() ->
                expectFlagsAndOperands []
                    (Command.build (,)
                        |> Command.optionWithStringArg "first-name"
                        |> Command.optionWithStringArg "last-name"
                        |> Command.toCommand
                    )
                    { flags = [], operands = [] }
        , test "gets operand from the front" <|
            \() ->
                expectFlagsAndOperands
                    [ "operand", "--verbose", "--dry-run" ]
                    (Command.build (,,)
                        |> Command.expectFlag "verbose"
                        |> Command.expectFlag "dry-run"
                        |> Command.toCommand
                    )
                    { flags = [ Flag "--verbose", Flag "--dry-run" ]
                    , operands = [ "operand" ]
                    }
        , test "gets operand from the back" <|
            \() ->
                expectFlagsAndOperands
                    [ "--verbose", "--dry-run", "operand" ]
                    (Command.build (,,)
                        |> Command.expectFlag "verbose"
                        |> Command.expectFlag "dry-run"
                        |> Command.toCommand
                    )
                    { flags = [ Flag "--verbose", Flag "--dry-run" ]
                    , operands = [ "operand" ]
                    }

        -- , test "gets operand from the front when args are used" <|
        --     \() ->
        --         expectFlagsAndOperands
        --             [ "operand", "--first-name", "Will", "--last-name", "Riker" ]
        --             (Command.build (,)
        --                 |> Command.optionWithStringArg "first-name"
        --                 |> Command.optionWithStringArg "last-name"
        --                 |> Command.toCommand
        --             )
        --             { flags = [ Option "--first-name" "Will", Option "--last-name" "Riker" ]
        --             , operands = [ "operand" ]
        --             }
        -- , test "gets operand from the back when args are present" <|
        --     \() ->
        --         [ "--first-name", "Will", "--last-name", "Riker", "operand" ]
        --             |> Command.flagsAndOperands
        --                 (Command.build FullName
        --                     |> Command.optionWithStringArg "first-name"
        --                     |> Command.optionWithStringArg "last-name"
        --                     |> Command.toCommand
        --                 )
        --             |> expectFlagsAndOperands
        --                 { flags = [ "--first-name", "Will", "--last-name", "Riker" ]
        --                 , operands = [ "operand" ]
        --                 }
        -- , test "gets operand when there are no options" <|
        --     \() ->
        --         [ "operand" ]
        --             |> Command.flagsAndOperands
        --                 (Command.build identity
        --                     |> Command.expectOperand "foo"
        --                     |> Command.toCommand
        --                 )
        --             |> expectFlagsAndOperands
        --                 { flags = []
        --                 , operands = [ "operand" ]
        --                 }
        ]


expectFlagsAndOperands :
    List String
    -> Command.Command decodesTo
    -> { flags : List ParsedOption, operands : List String }
    -> Expectation
expectFlagsAndOperands argv command expected =
    flagsAndOperands (Command.getUsageSpecs command) argv
        |> (\{ flags, operands } -> { flags = flags, operands = operands })
        |> Expect.equal expected