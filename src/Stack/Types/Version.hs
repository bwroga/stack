{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE ViewPatterns #-}

-- | Versions for packages.

module Stack.Types.Version
  (Version
  ,Cabal.VersionRange -- TODO in the future should have a newtype wrapper
  ,IntersectingVersionRange(..)
  ,VersionCheck(..)
  ,versionRangeText
  ,withinRange
  ,Stack.Types.Version.intersectVersionRanges
  ,toMajorVersion
  ,latestApplicableVersion
  ,checkVersion
  ,nextMajorVersion
  ,UpgradeTo(..)
  ,minorVersion
  ,stackVersion
  ,stackMinorVersion)
  where

import           Stack.Prelude hiding (Vector)
import           Data.Aeson.Extended
import           Data.List
import qualified Data.Set as Set
import qualified Data.Text as T
import           Distribution.Text (disp)
import qualified Distribution.Version as Cabal
import           Distribution.Version (Version, versionNumbers, withinRange)
import qualified Paths_stack as Meta
import           Text.PrettyPrint (render)

-- | A Package upgrade; Latest or a specific version.
data UpgradeTo = Specific Version | Latest deriving (Show)

newtype IntersectingVersionRange =
    IntersectingVersionRange { getIntersectingVersionRange :: Cabal.VersionRange }
    deriving Show

instance Semigroup IntersectingVersionRange where
    IntersectingVersionRange l <> IntersectingVersionRange r =
        IntersectingVersionRange (l `Cabal.intersectVersionRanges` r)

instance Monoid IntersectingVersionRange where
    mempty = IntersectingVersionRange Cabal.anyVersion
    mappend = (<>)

-- | Display a version range
versionRangeText :: Cabal.VersionRange -> Text
versionRangeText = T.pack . render . disp

-- | A modified intersection which also simplifies, for better display.
intersectVersionRanges :: Cabal.VersionRange -> Cabal.VersionRange -> Cabal.VersionRange
intersectVersionRanges x y = Cabal.simplifyVersionRange $ Cabal.intersectVersionRanges x y

-- | Returns the first two components, defaulting to 0 if not present
toMajorVersion :: Version -> Version
toMajorVersion v =
  case versionNumbers v of
    []    -> Cabal.mkVersion [0, 0]
    [a]   -> Cabal.mkVersion [a, 0]
    a:b:_ -> Cabal.mkVersion [a, b]

-- | Given a version range and a set of versions, find the latest version from
-- the set that is within the range.
latestApplicableVersion :: Cabal.VersionRange -> Set Version -> Maybe Version
latestApplicableVersion r = listToMaybe . filter (`withinRange` r) . Set.toDescList

-- | Get the next major version number for the given version
nextMajorVersion :: Version -> Version
nextMajorVersion v =
  case versionNumbers v of
    []    -> Cabal.mkVersion [0, 1]
    [a]   -> Cabal.mkVersion [a, 1]
    a:b:_ -> Cabal.mkVersion [a, b + 1]

data VersionCheck
    = MatchMinor
    | MatchExact
    | NewerMinor
    deriving (Show, Eq, Ord)
instance ToJSON VersionCheck where
    toJSON MatchMinor = String "match-minor"
    toJSON MatchExact = String "match-exact"
    toJSON NewerMinor = String "newer-minor"
instance FromJSON VersionCheck where
    parseJSON = withText expected $ \t ->
        case t of
            "match-minor" -> return MatchMinor
            "match-exact" -> return MatchExact
            "newer-minor" -> return NewerMinor
            _ -> fail ("Expected " ++ expected ++ ", but got " ++ show t)
      where
        expected = "VersionCheck value (match-minor, match-exact, or newer-minor)"

checkVersion :: VersionCheck -> Version -> Version -> Bool
checkVersion check (versionNumbers -> wanted) (versionNumbers -> actual) =
    case check of
        MatchMinor -> and (take 3 matching)
        MatchExact -> length wanted == length actual && and matching
        NewerMinor -> and (take 2 matching) && newerMinor
  where
    matching = zipWith (==) wanted actual

    getMinor (_a:_b:c:_) = Just c
    getMinor _ = Nothing

    newerMinor =
        case (getMinor wanted, getMinor actual) of
            (Nothing, _) -> True
            (Just _, Nothing) -> False
            (Just w, Just a) -> a >= w

-- | Get minor version (excludes any patchlevel)
minorVersion :: Version -> Version
minorVersion = Cabal.mkVersion . take 3 . versionNumbers

-- | Current Stack version
stackVersion :: Version
stackVersion = Cabal.mkVersion' Meta.version

-- | Current Stack minor version (excludes patchlevel)
stackMinorVersion :: Version
stackMinorVersion = minorVersion stackVersion
