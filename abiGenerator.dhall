let Text/concatMapSep =
        ./Prelude/Text/concatMapSep
      ? https://prelude.dhall-lang.org/Text/concatMapSep

let Text/concatMap =
        ./Prelude/Text/concatMap
      ? https://prelude.dhall-lang.org/Text/concatMap

let List/map =
        ./Prelude/List/map
      ? https://prelude.dhall-lang.org/List/map

let List/filter =
        ./Prelude/List/filter
      ? https://prelude.dhall-lang.org/List/filter

let schema = ./abiSchema.dhall

let FunArg = schema.FunArg

let SimpleArg = schema.SimpleArg

let ComplexArg = schema.ComplexArg

let SimpleIArg = { index : Natural, value : SimpleArg }

let isConstructor
    : schema.Op → Bool
    =   λ(op : schema.Op)
      → merge
        { Function =
            λ(_ : schema.Fun) → False
        , Fallback =
            λ(_ : schema.Fallback) → False
        , Event =
            λ(_ : schema.Event) → False
        , Constructor =
            λ(_ : schema.Constructor) → True
        }
        op

let hasConstructor
    : List schema.Op → Bool
    =   λ(ops : List schema.Op)
      → Optional/fold
        schema.Op
        (List/head schema.Op (List/filter schema.Op isConstructor ops))
        Bool
        (λ(_ : schema.Op) → True)
        False

let toSimpleArg
    : FunArg → SimpleArg
    =   λ(arg : FunArg)
      → merge
        { Simple =
            λ(arg : SimpleArg) → arg.{ name, type }
        , Complex =
            λ(arg : ComplexArg) → arg.{ name, type }
        }
        arg

let toSimpleArgs
    : List FunArg → List SimpleArg
    = List/map FunArg SimpleArg toSimpleArg

let funIndexedArgToDhallFun
    : SimpleIArg → Text
    =   λ(iarg : SimpleIArg)
      → "λ(arg${Natural/show
                iarg.index} : { ${iarg.value.type} : Text, def : Text })"

let funArgsToDhallFun
    : List FunArg → Text
    =   λ(args : List FunArg)
      → Text/concatMap
        SimpleIArg
        (λ(arg : SimpleIArg) → " → " ++ funIndexedArgToDhallFun arg)
        (List/indexed SimpleArg (toSimpleArgs args))

let funReturnToDhallType
    : List FunArg → Text
    =   λ(outputs : List FunArg)
      → Optional/fold
        SimpleArg
        (List/head SimpleArg (toSimpleArgs outputs))
        Text
        (λ(arg : SimpleArg) → arg.type)
        "void"

let funSignature
    : List FunArg → Text
    =   λ(args : List FunArg)
      → Text/concatMap
        SimpleArg
        (λ(arg : SimpleArg) → "/${arg.type}")
        (toSimpleArgs args)

let funToDhallName
    : schema.Fun → Text
    = λ(fun : schema.Fun) → "${fun.name}${funSignature fun.inputs}"

let createFun
    : schema.Backend → Text → schema.Constructor → Text
    =   λ(backend : schema.Backend)
      → λ(name : Text)
      → λ(constructor : schema.Constructor)
      → ''
        create${funSignature constructor.inputs} =
            λ(tag : Text)
           ${funArgsToDhallFun constructor.inputs}
            → { address = ${backend.createValue constructor}
              , def = ${backend.createDef constructor}
              }
        ''

let send
    : schema.Backend → schema.Fun → Text
    =   λ(backend : schema.Backend)
      → λ(fun : schema.Fun)
      → ''
        send/${funToDhallName fun} =
              λ(address : { address : Text, def : Text })${funArgsToDhallFun
                                                           fun.inputs}
            → { void = ${backend.sendValue fun}
              , def = ${backend.sendDef fun}
              }
        ''

let call
    : schema.Backend → schema.Fun → Text
    =   λ(backend : schema.Backend)
      → λ(fun : schema.Fun)
      → ''
        call/${funToDhallName fun} =
              λ(tag : Text)
            → λ(address : { address : Text, def : Text })${funArgsToDhallFun
                                                           fun.inputs}
            → { ${funReturnToDhallType fun.outputs} = ${backend.callValue fun}
           , def = ${backend.callDef fun}
              }
        ''

let defaultConstructor =
      schema.Op.Constructor
      { inputs =
          [] : List FunArg
      , payable =
          False
      , stateMutability =
          ""
      , type =
          "constructor"
      }

let abiOpToDhall
    : Text → schema.Backend → schema.Op → Text
    =   λ(name : Text)
      → λ(backend : schema.Backend)
      → λ(op : schema.Op)
      → merge
        { Function =
            λ(fun : schema.Fun) → "${send backend fun}\n, ${call backend fun}"
        , Fallback =
            λ(fallback : schema.Fallback) → "fallback = {=}"
        , Event =
            λ(event : schema.Event) → "event/${event.name} = {=}"
        , Constructor =
            createFun backend name
        }
        op

let abiToDhall
    : Text → schema.Backend → schema.Abi → Text
    =   λ(name : Text)
      → λ(backend : schema.Backend)
      → λ(ops : schema.Abi)
      → ''
        let lib = ../lib/default
        
        let backend = ../lib/backend
        
        let name = "${name}" 
        
        in  { ${Text/concatMapSep
                ''
                
                , ''
                schema.Op
                (abiOpToDhall name backend)
                (   (       if hasConstructor ops
                      
                      then  [] : List schema.Op
                      
                      else  [ defaultConstructor ]
                    )
                  # ops
                )}
            }
        ''

in  abiToDhall
