module Cli.Program exposing (Config, StatefulProgram, StatelessProgram, add, config, stateful, stateless)

{-|


## Config

A `Cli.Program.Config` is created with `empty`. Then `OptionsParser`s are added
to it. Finally, you create a `Cli.Program.StatelessProgram` using `stateless` or
`stateful`.

@docs config, Config, add


## `Program`s

@docs stateless, stateful
@docs StatelessProgram, StatefulProgram

-}

import Cli.ExitStatus exposing (ExitStatus)
import Cli.LowLevel
import Cli.OptionsParser as OptionsParser exposing (OptionsParser)
import Cli.OptionsParser.BuilderState as BuilderState
import List.Extra
import TypoSuggestion


type RunResult match
    = SystemMessage ExitStatus String
    | CustomMatch match


{-| A `Cli.Program.Config` is used to build up a set of `OptionsParser`s for your
Command-Line Interface, as well as its meta-data such as version number.
-}
type Config msg
    = Config
        { optionsParsers : List (OptionsParser msg BuilderState.NoMoreOptions)
        , version : String
        }


{-| Create a `Config` with no `OptionsParser`s. Use `Cli.Program.add` to add
`OptionsParser`s.
-}
config : { version : String } -> Config decodesTo
config { version } =
    Config
        { version = version
        , optionsParsers = []
        }


{-| Add an `OptionsParser` to your `Cli.Program.Config`.
-}
add : OptionsParser msg anything -> Config msg -> Config msg
add optionsParser (Config ({ optionsParsers } as programRecord)) =
    Config
        { programRecord
            | optionsParsers = optionsParsers ++ [ OptionsParser.end optionsParser ]
        }


{-| -}
type alias StatelessProgram msg =
    Platform.Program (List String) () msg


{-| -}
stateless : ProgramOptions msg options -> StatelessProgram msg
stateless options =
    Platform.programWithFlags
        { init = init options
        , update = \msg model -> ( (), Cmd.none )
        , subscriptions = \_ -> Sub.none
        }


{-| -}
type alias StatefulProgram model msg =
    Platform.Program (List String) (StatefulProgramModel model) msg


type alias StatefulOptions msg model cliOptions =
    { printAndExitFailure : String -> Cmd msg
    , printAndExitSuccess : String -> Cmd msg
    , init : cliOptions -> ( model, Cmd msg )
    , update : msg -> model -> ( model, Cmd msg )
    , subscriptions : model -> Sub msg
    , config : Config cliOptions
    }


{-| A `stateful` program can have a model that it creates and updates via `init`
and `update`. It also has `subscriptions`. See
[the `Curl.elm` example](https://github.com/dillonkearns/elm-cli-options-parser/blob/master/examples/src/Curl.elm).
-}
stateful :
    StatefulOptions msg model cliOptions
    -> Platform.Program (List String) (StatefulProgramModel model) msg
stateful options =
    Platform.programWithFlags
        { init = statefulInit options
        , update =
            \msg model ->
                case model of
                    UserModel actualModel ->
                        let
                            ( model, cmd ) =
                                options.update msg actualModel
                        in
                        ( UserModel model, cmd )

                    ShowSystemMessage ->
                        ( ShowSystemMessage, Cmd.none )
        , subscriptions =
            \model ->
                case model of
                    UserModel actualModel ->
                        options.subscriptions actualModel

                    ShowSystemMessage ->
                        Sub.none
        }


type alias ProgramOptions decodesTo options =
    { printAndExitFailure : String -> Cmd decodesTo
    , printAndExitSuccess : String -> Cmd decodesTo
    , init : options -> Cmd decodesTo
    , config : Config options
    }


init :
    ProgramOptions msg options
    -> List String
    -> ( (), Cmd msg )
init options argv =
    let
        matchResult : RunResult options
        matchResult =
            run options.config argv

        cmd =
            case matchResult of
                SystemMessage exitStatus message ->
                    case exitStatus of
                        Cli.ExitStatus.Failure ->
                            options.printAndExitFailure message

                        Cli.ExitStatus.Success ->
                            options.printAndExitSuccess message

                CustomMatch msg ->
                    options.init msg
    in
    ( (), cmd )


type StatefulProgramModel model
    = ShowSystemMessage
    | UserModel model


statefulInit :
    StatefulOptions msg model cliOptions
    -> List String
    -> ( StatefulProgramModel model, Cmd msg )
statefulInit options argv =
    let
        matchResult : RunResult cliOptions
        matchResult =
            run options.config argv

        cmd =
            case matchResult of
                SystemMessage exitStatus message ->
                    case exitStatus of
                        Cli.ExitStatus.Failure ->
                            ( ShowSystemMessage, options.printAndExitFailure message )

                        Cli.ExitStatus.Success ->
                            ( ShowSystemMessage, options.printAndExitSuccess message )

                CustomMatch msg ->
                    let
                        ( model, cmd ) =
                            options.init msg
                    in
                    ( UserModel model, cmd )
    in
    cmd


run : Config msg -> List String -> RunResult msg
run (Config { optionsParsers, version }) argv =
    let
        programName =
            case argv of
                first :: programPath :: _ ->
                    programPath
                        |> String.split "/"
                        |> List.Extra.last
                        |> Maybe.withDefault errorMessage

                _ ->
                    errorMessage

        errorMessage =
            "TODO - show error message explaining that user needs to pass unmodified `process.argv` from node here."

        matchResult =
            Cli.LowLevel.try optionsParsers argv
    in
    case matchResult of
        Cli.LowLevel.NoMatch unexpectedOptions ->
            if unexpectedOptions == [] then
                "\nNo matching optionsParser...\n\nUsage:\n\n"
                    ++ Cli.LowLevel.helpText programName optionsParsers
                    |> SystemMessage Cli.ExitStatus.Failure

            else
                unexpectedOptions
                    |> List.map
                        (TypoSuggestion.toMessage
                            (optionsParsers
                                |> List.map
                                    (\optionsParser ->
                                        { usageSpecs = OptionsParser.getUsageSpecs optionsParser
                                        , subCommand = OptionsParser.getSubCommand optionsParser
                                        }
                                    )
                            )
                        )
                    |> String.join "\n"
                    |> SystemMessage Cli.ExitStatus.Failure

        Cli.LowLevel.ValidationErrors validationErrors ->
            ("Validation errors:\n\n"
                ++ (validationErrors
                        |> List.map
                            (\{ name, invalidReason, valueAsString } ->
                                "`"
                                    ++ name
                                    ++ "` failed a validation. "
                                    ++ invalidReason
                                    ++ "\nValue was:\n"
                                    ++ valueAsString
                            )
                        |> String.join "\n"
                   )
            )
                |> SystemMessage Cli.ExitStatus.Failure

        Cli.LowLevel.Match msg ->
            msg
                |> CustomMatch

        Cli.LowLevel.ShowHelp ->
            Cli.LowLevel.helpText programName optionsParsers
                |> SystemMessage Cli.ExitStatus.Success

        Cli.LowLevel.ShowVersion ->
            programName
                ++ " version "
                ++ version
                |> SystemMessage Cli.ExitStatus.Success
