{-# LANGUAGE FlexibleContexts, FlexibleInstances, TypeSynonymInstances, OverloadedStrings #-}
module Solver.PP where

import Data.Char
import qualified Data.IntSet as Set
import Data.List
import Solver.Syntax

--------------------------------------------------------------------------------
-- Auto-generation of names

replacePunctuation ('(':cs)        = replacePunctuation cs
replacePunctuation (')':cs)        = replacePunctuation cs
replacePunctuation ('=':'>':cs)    = replacePunctuation cs
replacePunctuation (c:cs)
    | isPunctuation c || isSpace c = '_' : replacePunctuation cs
    | otherwise                    = toLower c : replacePunctuation cs
replacePunctuation []              = []

axiomAutoName :: QPred -> Id
axiomAutoName qp = fromString (replacePunctuation (ppx qp))

requirementAutoName :: [Pred] -> Pred -> Id
requirementAutoName ps q = fromString (replacePunctuation (intercalate "," (map ppx ps) ++ " requires " ++ ppx q))

--------------------------------------------------------------------------------
-- Pretty-printing class and utilities

ppx :: PP t => t -> String
ppx = pp 0

-- This is super-mondo-efficient
printx :: PP t => t -> IO ()
printx x | null s         = return ()
         | last s == '\n' = putStr s
         | otherwise      = putStrLn s
    where s = pp 0 x

class PP t
    where pp :: Int -> t -> String

parens :: String -> String
parens s = '(' : s ++ ")"

--------------------------------------------------------------------------------
-- Standard containers

instance {-# OVERLAPPING #-} PP t => PP [t]
    where pp _ ts = '[' : intercalate ", " (map (pp 0) ts) ++ "]"

instance {-# OVERLAPPING #-} (PP a, PP b) => PP (a,b)
    where pp _ (a,b) = '(' : pp 0 a ++ ", " ++ pp 0 b ++ ")"

instance {-# OVERLAPPING #-} (PP a, PP b, PP c) => PP (a, b, c)
    where pp _ (a, b, c) = '(' : pp 0 a ++ ", " ++ pp 0 b ++ ", " ++ pp 0 c ++ ")"

--------------------------------------------------------------------------------
-- AST pretty-printers

toPeanoNumber (TyCon (Kinded "Z" _)) = return 0
toPeanoNumber (TyCon (Kinded "S" _) :@ ty) =
    do n <- toPeanoNumber ty
       return (n + 1)
toPeanoNumber _ = Nothing

instance PP Id
    where pp _ s = fromId s

instance PP Kind
    where pp _ KStar = "*"
          pp _ (KVar v) = ppx v
          pp _ KNat = "nat"
          pp _ KArea = "area"
          pp _ KLabel = "label"
          pp n (KFun k k') =
              (if n > 0 then parens else id)
              (pp 1 k ++ " -> " ++ pp 0 k')

instance PP t => PP (Kinded t)
    where pp n (Kinded x _) = pp n x

instance PP Type
    where pp n t =
              case toPeanoNumber t of
                Just n -> 'P' : show n
                _ -> pp' n t
              where pp' _ (TyCon (Kinded s _)) = ppx s
                    pp' _ (TyVar (Kinded s _)) = ppx s
                    pp' _ (TyGen n)            = '_' : show n
                    pp' _ (TyLit n)            = show n
                    pp' n (t :@ t')            = (if n > 0 then parens else id)
                                                 (pp 0 t ++ " " ++ pp 1 t')

instance PP Flag
    where pp _ Inc = ""
          pp _ Exc = "fails"

instance PP Pred
    where pp _ (Pred name types x _) = intercalate " " (ppx name : map (pp 1) types) ++ if x == Exc then ' ' : pp 0 x else ""

instance PP t => PP (Qual t)
    where pp _ ([] :=> p)  = pp 0 p
          pp _ (qs :=> p)  = pp 0 p ++ " if " ++ intercalate ", " (map (pp 0) qs)

instance {-# OVERLAPPING #-} PP t => PP (Scheme t)
    where pp _ (Forall ks t) = "forall " ++ intercalate ", " (map ppx ks) ++ ". " ++ ppx t

instance PP Name
    where pp _ (AutoGenerated _) = ""
          pp _ (UserSupplied s) = ppx s

instance {-# OVERLAPPING #-} PP Axiom
    where pp _ (Ax name qps) = f (ppx name) ++ intercalate "; " (map (pp 0) qps)
              where f "" = ""
                    f s = s ++ ": "

instance {-# OVERLAPPING #-} PP Axioms
    where pp _ axs = intercalate "\n" (map ((++ ".") . pp 0) axs)

names = tail loop
    where loop = "" : [l : s | s <- loop, l <- ['a'..'z']]

instance {-# OVERLAPPING #-} PP (Id, [FunDep])
    where pp _ (clName, fds) = intercalate " " (ppx clName:vars) ++ " | " ++ intercalate ", " (map ppFd fds)
              where ppFd ([] :~> determined) = "~> " ++ intercalate " " (map (vars !!) determined)
                    ppFd (determining :~> determined) = intercalate " " (map (vars !!) determining) ++ " ~> " ++ intercalate " " (map (vars !!) determined)
                    highIdx = maximum (concatMap (\(ts :~> us) -> ts ++ us) fds)
                    vars = take (highIdx + 1) names

instance {-# OVERLAPPING #-} PP FunDeps
    where pp _ fds = intercalate "\n" (map ((++ ".") . ppx) fds)

instance {-# OVERLAPPING #-} PP Requirement
    where pp _ (Requires ps qs) = intercalate ", " (map ppx ps) ++ " requires " ++ intercalate ", " (map (ppx . snd) qs)

instance {-# OVERLAPPING #-} PP Requirements
    where pp _ rqs = intercalate "\n" (map ((++ ".") . ppx) rqs)

instance {-# OVERLAPPING #-} PP (Id, [Int])
    where pp _ (clName, ops) = intercalate " " (ppx clName : vars)  ++ " | " ++ intercalate ", " (map ppOp ops)
              where ppOp n = "opaque " ++ (vars !! n)
                    highIdx = maximum ops
                    vars = take (highIdx + 1) names

instance {-# OVERLAPPING #-} PP Opacities
    where pp _ ops = intercalate "\n" (map ((++ ".") . ppx) ops)

instance PP AxId
    where pp _ (AxId s (Just n)) = ppx s ++ "!" ++ show n
          pp _ (AxId s Nothing)  = ppx s

instance PP Spin where pp _ s = show s

instance PP Binding
    where pp _ (Kinded v _ :-> t) = ppx v ++ " :-> " ++ ppx t

instance PP Subst
    where pp _ (S _ ps) = '[' : (intercalate "; " (map ppx ps)) ++ "]"

instance PP TaggedSubst
    where pp _ (TS _ ps) = '[' : (intercalate "; " ["[" ++ show i ++ "] " ++ ppx b | (i, b) <- ps]) ++ "]"


showProofSpin Proving    = "Proved: "
showProofSpin Disproving = "Disproved: "

instance PP Proof
    where pp _ (PAx id axid tys skips subproofs) =
              ppx id ++ ":" ++
              ppx axid ++
              "{" ++ intercalate ", " (map ppx tys) ++ "}" ++
              (if null skips then "" else "[" ++ intercalate ", " [ show i ++ ":" ++ ppx p | (i,p) <- skips ] ++ "]") ++
              "(" ++ intercalate ", " (map ppx subproofs) ++ ")"
          pp _ (PCases id cases) =
              ppx id ++ ":cases {" ++ intercalate "; " [ ppx s ++ " -> " ++ ppx s' ++ " " ++ ppx pr | (s, s', pr) <- cases ] ++ "}"
          pp _ (PComputedCases id tys _ _ _) =
              ppx id ++ ":computed{" ++ intercalate ", " (map ppx tys) ++ "}"
          pp _ (PAssump id aid) = ppx id ++ ":assumption(" ++ ppx aid ++ ")"
          pp _ (PRequired id rid pr) = ppx id ++ ":required(" ++ ppx rid ++ ", " ++ ppx pr ++")"
          pp _ (PClause _ axid tys ps) = ppx axid ++ "{" ++ intercalate ", " (map ppx tys) ++ "}(" ++ intercalate ", " (map ppx ps) ++ ")"
          pp _ (PFrom pat p p') = "(" ++ ppx pat ++ " <- " ++ ppx p ++ ") => " ++ ppx p'
          pp _ (PSkip axid (i, p)) = concat ["[", ppx axid, ":", show i, ":", ppx p, "]"]
          pp _ PExFalso = "ex falso"
          pp _ PInapplicable = "inapplicable"

instance PP (PId -> Proof)
    where pp n f = pp n (f "_")

instance PP RqImpls
    where pp _ (RqImpls rqis) = intercalate "\n" [ppx rid ++ ':' : (concatMap ("\n    " ++) (map ppImpl cs)) | (rid, cs) <- rqis]
              where ppImpl (pats, pr) = '(' : intercalate ", " (map ppx pats) ++ ") -> " ++ ppx pr

instance PP ProofPattern
    where pp _ (Pat axid ts vs) = ppx axid ++ '{' : intercalate ", " (map ppx ts) ++ "}(" ++ intercalate ", " (map ppx vs) ++ ")"
          pp _ Wild             = "_"

instance PP Set.IntSet
    where pp _ s = "{" ++ intercalate "," (map show (Set.toList s)) ++ "}"
