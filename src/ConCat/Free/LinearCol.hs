{-# LANGUAGE DataKinds #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE CPP #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE PartialTypeSignatures #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeApplications #-}

{-# OPTIONS_GHC -Wall #-}
{-# OPTIONS_GHC -fno-warn-unused-imports #-}  -- TEMP

-- | Some experiments in formulating constrained linear optimization problems.

module ConCat.Free.LinearCol where

import Prelude hiding (id,(.),zipWith)

import GHC.Generics (Par1(..),(:*:)(..),(:.:)(..))
import Data.Constraint

import Data.Pointed (Pointed(..))
import Data.Key (Keyed(..),Zip(..),Adjustable(..))

import Control.Newtype

import ConCat.Misc (inNew,inNew2)
import ConCat.Orphans ()
import ConCat.Free.VectorSpace
import ConCat.Category

{--------------------------------------------------------------------
    Linear maps
--------------------------------------------------------------------}

-- Linear map from a s to b s
infixr 1 :-*
type (a :-* b) s = a (b s)

-- TODO: consider instead
-- 
--   type Linear = (:.:)
-- 
-- so that Linear itself forms a vector space.

-- Apply a linear map
infixr 9 $*
($*), lapplyL :: (Zip a, Foldable a, Zip b, Zeroable b, Num s)
              => (a :-* b) s -> a s -> b s
bs $* a = sumV (zipWith (*^) a bs)

lapplyL = ($*)

zeroL :: (Zeroable a, Zeroable b, Num s) => (a :-* b) s
zeroL = unComp1 zeroV
-- zeroL = point zeroV

{--------------------------------------------------------------------
    Other operations
--------------------------------------------------------------------}

scaleL :: (Adjustable a, Keyed a, Zeroable a, Num s)
       => s -> (a :-* a) s
scaleL s = mapWithKey (flip replace s) zeroL

-- mapWithKey :: Keyed f => (Key f -> a -> b) -> f a -> f b
-- replace :: Adjustable f => Key f -> a -> f a -> f a

---- Category

-- Identity linear map
idL :: (Adjustable a, Keyed a, Zeroable a, Num s)
    => (a :-* a) s
idL = scaleL 1

-- Compose linear transformations
(@.) :: (Functor a, Foldable b, Zip b, Zeroable c, Zip c, Num s)
     => (b :-* c) s -> (a :-* b) s -> (a :-* c) s
bc @. ab = (bc $*) <$> ab

-- (@.) = fmap . ($*)

---- Product

exlL :: (Zeroable a, Keyed a, Adjustable a, Zeroable b, Num s)
     => (a :*: b :-* a) s
exlL = idL :*: zeroL

exrL :: (Zeroable b, Keyed b, Adjustable b, Zeroable a, Num s)
     => (a :*: b :-* b) s
exrL = zeroL :*: idL

forkL :: Zip a => (a :-* b) s -> (a :-* c) s -> (a :-* b :*: c) s
forkL = zipWith (:*:)

---- Coproduct as direct sum (represented as Cartesian product)

inlL :: (Zeroable a, Keyed a, Adjustable a, Zeroable b, Num s)
     => (a :-* a :*: b) s
inlL = (:*: zeroV) <$> idL

inrL :: (Zeroable a, Zeroable b, Keyed b, Adjustable b, Num s)
     => (b :-* a :*: b) s
inrL = (zeroV :*:) <$> idL

joinL :: (a :-* c) s -> (b :-* c) s -> (a :*: b :-* c) s
joinL = (:*:)


{--------------------------------------------------------------------
    Category
--------------------------------------------------------------------}

newtype L s a b = L ((V s a :-* V s b) s)

instance Newtype (L s a b) where
  type O (L s a b) = (V s a :-* V s b) s
  pack ab = L ab
  unpack (L ab) = ab

type OkLF' f = (Foldable f, Zeroable f, Zip f, Keyed f, Adjustable f)

type OkLM' s a = (HasV s a, HasL (V s a), Num s)

class    OkLM' s a => OkLM s a
instance OkLM' s a => OkLM s a

instance Category (L s) where
  type Ok (L s) = OkLM s
  id = pack idL
  (.) = inNew2 (@.)

instance OpCon (,) (Sat (OkLM s)) where inOp = Entail (Sub Dict)

instance ProductCat (L s) where
  -- type Prod (L s) = (,)
  exl = pack exlL
  exr = pack exrL
  (&&&) = inNew2 forkL

-- Can I still have coproducts? Seems problematic without a definable Coprod

-- instance CoproductCat (L s) where
--   -- type Coprod (L s) = (,)
--   inl = pack inlL
--   inr = pack inrL
--   (|||) = inNew2 joinL

-- We can't make a ClosedCat instance compatible with the ProductCat instance.
-- We'd have to change the latter to use the tensor product.

-- Conversion to linear map
lapply :: (Num s, Oks (L s) [a,b]) => L s a b -> (a -> b)
lapply (L gfa) = unV . lapplyL gfa . toV

-- lapplyL :: ... => (a :-* b) s -> a s -> b s


class OkLF' f => HasL f where
  -- | Law: @'linear' . 'lapply' == 'id'@ (but not the other way around)
  linear' :: forall s g. (Num s, OkLF' g) => (f s -> g s) -> (f :-* g) s

instance HasL Par1 where
  linear' f = Par1 (f (Par1 1))

--       f           :: Par1 s -> b s
--       f (Par1 1)  :: b s
-- Par1 (f (Par1 1)) :: Par1 (b s)

instance (HasL f, HasL g) => HasL (f :*: g) where
  linear' q = linear' (q . (:*: zeroV)) `joinL` linear' (q . (zeroV :*:))

--          q                :: (f :*: g) s -> h s
--              (:*: zeroV)  :: f s -> (f :*: g) s
--          q . (:*: zeroV)  :: f s -> h s
-- linear' (q . (:*: zeroV)) :: (f :-* h) s

linear :: (OkLM s a, OkLM s b) => (a -> b) -> L s a b
linear f = L (linear' (inV f))

-- f :: a -> b
-- inV f :: V s a s -> V s b s

{--------------------------------------------------------------------
    Functors
--------------------------------------------------------------------}

data Lapply s

instance FunctorC (Lapply s) (L s) (->) where fmapC = lapply

data Linear s

instance FunctorC (Linear s) (->) (L s) where fmapC = linear
