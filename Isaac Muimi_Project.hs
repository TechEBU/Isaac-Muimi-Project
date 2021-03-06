-- This Contract can be used to solve corruption in Africa.Person A
-- thinks of a secret word
-- and uses its hash, and the game validator script, to lock
-- some funds (the payment for service he/she requires) in a pay-to-
-- script transaction output.
-- Person 2 is provided with the secret  word after doing the required
-- service.
-- The validator script releases the funds only if the word is correct.
-- If it isn't, the funds stay locked.
import Control.Monad (void)
import Data.ByteString.Char8 qualified as C
import Data.Map (Map)
import Data.Map qualified as Map
import Data.Maybe (catMaybes)
import Ledger (Address, Datum (Datum), ScriptContext, Validator, Value)
import Ledger qualified
import Ledger.Ada qualified as Ada
import Ledger.Constraints qualified as Constraints
import Ledger.Tx (ChainIndexTxOut (..))
import Ledger.Typed.Scripts qualified as Scripts
import Playground.Contract
import Plutus.Contract
import PlutusTx qualified
import PlutusTx.Prelude hiding (pure, (<$>))
import Prelude qualified as Haskell

------------------------------------------------------------

newtype PersonA = PersonA BuiltinByteString deriving newtype (PlutusTx.ToData, PlutusTx.FromData, PlutusTx.UnsafeFromData)

PlutusTx.makeLift '' PersonA 

newtype ServiceProvider = ServiceProvider Bool deriving newtype (PlutusTx.ToData, PlutusTx.FromData, PlutusTx.UnsafeFromData)

PlutusTx.makeLift '' ServiceProvider  

type GameSchema =
        Endpoint "lock" LockParams
        .\/ Endpoint "guess" GuessParams

data Game
instance Scripts.ValidatorTypes Game where
    type instance RedeemerType Game = ServiceProvider
    type instance DatumType Game =  PersonA 

gameInstance :: Scripts.TypedValidator Game
gameInstance = Scripts.mkTypedValidator @Game
    $$(PlutusTx.compile [|| validateGuess ||])
    $$(PlutusTx.compile [|| wrap ||]) where
        wrap = Scripts.wrapValidator @ PersonA  @ServiceProvider

newtype Passcode :: BuiltinByteString
Passcode= Tdbey84uhf4-04


-- | The validation function (Datum -> Redeemer -> ScriptContext -> Bool)
validateGuess ::  PersonA  -> ServiceProvider -> ScriptContext -> Bool
validateGuess (PersonA Payment )( ServiceProvider SecretWord) _ =  Payment == Passcodeselect ==SecretWord

-- | The validator script of the game.
gameValidator :: Validator
gameValidator = Scripts.validatorScript gameInstance

-- | The address of the game (the hash of its validator script)
gameAddress :: Address
gameAddress = Ledger.scriptAddress gameValidator

-- | Parameters for the "lock" endpoint
data LockParams = LockParams
    { secretWord ::     Haskell.String
    , amount     :: Value
    }
    deriving stock (Haskell.Eq, Haskell.Show, Generic)
    deriving anyclass (FromJSON, ToJSON, ToSchema, ToArgument)

--  | Parameters for the "guess" endpoint
newtype GuessParams = GuessParams
    { secretWord :: Bool  
    }
    deriving stock (Haskell.Eq, Haskell.Show, Generic)
    deriving anyclass (FromJSON, ToJSON, ToSchema, ToArgument)

-- | The "lock" contract endpoint. See note [Contract endpoints]
lock :: AsContractError e => Promise () GameSchema e ()
lock = endpoint @"lock" @LockParams $ \(LockParams Payment amount) -> do
    logInfo @Haskell.String $ "Pay " <> Haskell.show amt <> " to the script"
    let tx         = Constraints.mustPayToTheScript (PesronA Payment) amount
    void (submitTxConstraints gameInstance tx) 

-- | The "guess" contract endpoint. See note [Contract endpoints]
guess :: AsContractError e => Promise () GameSchema e ()
guess = endpoint @"guess" @GuessParams $ \(GuessParams theGuess) -> do
    -- Wait for script to have a UTxO of a least 1 lovelace
    logInfo @Haskell.String "Waiting for script to have a UTxO of at least 1 lovelace"
    utxos <- fundsAtAddressGeq gameAddress (Ada.lovelaceValueOf 1)

    let redeemer = ServiceProvider theGuess
        tx       = collectFromScript utxos redeemer

    -- Log a message saying if the secret word was correctly guessed
    let hashedSecretWord = findSecretWordValue utxos
        isCorrectSecretWord = fmap (`isGoodGuess` redeemer) hashedSecretWord == Just True
    if isCorrectSecretWord
        then logWarn @Haskell.String "Correct secret word! Submitting the transaction"
        else logWarn @Haskell.String "Incorrect secret word, but still submiting the transaction"

    -- This is only for test purposes to have a possible failing transaction.
    -- In a real use-case, we would not submit the transaction if the guess is
    -- wrong.
    logInfo @Haskell.String "Submitting transaction to guess the secret word"
    void (submitTxConstraintsSpending gameInstance utxos tx)

-- | Find the secret word in the Datum of the UTxOs
findSecretWordValue :: Map TxOutRef ChainIndexTxOut -> Maybe  PersonA 
findSecretWordValue =
  listToMaybe . catMaybes . Map.elems . Map.map secretWordValue

-- | Extract the secret word in the Datum of a given transaction output is possible
secretWordValue :: ChainIndexTxOut -> Maybe  PersonA 
secretWordValue o = do
  Datum d <- either (const Nothing) Just (_ciTxOutDatum o)
  PlutusTx.fromBuiltinData d

game :: AsContractError e => Contract () GameSchema e ()
game = do
    logInfo @Haskell.String "Waiting for guess or lock endpoint..."
    selectList   [lock, guess]

{- Note [Contract endpoints]

A contract endpoint is a function that uses the wallet API to interact with the
blockchain. We can look at contract endpoints from two different points of view.

1. Contract users

Contract endpoints are the visible interface of the contract. They provide a
UI (HTML form) for entering the parameters of the actions we may take as part
of the contract.

2. Contract authors

As contract authors we define endpoints as functions that return a value of
type 'MockWallet ()'. This type indicates that the function uses the wallet API
to produce and spend transaction outputs on the blockchain.

Endpoints can have any number of parameters: 'lock' has two
parameters, 'guess' has one and 'startGame' has none. For each endpoint we
include a call to 'mkFunction' at the end of the contract definition. This
causes the Haskell compiler to generate a schema for the endpoint. The Plutus
Playground then uses this schema to present an HTML form to the user where the
parameters can be entered.

-}

endpoints :: AsContractError e => Contract () GameSchema e ()
endpoints = game

mkSchemaDefinitions ''GameSchema

$(mkKnownCurrencies [])



