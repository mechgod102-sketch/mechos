# MechScope source-owned UI

This directory is the source authority for the MechScope interface.

The ISO build may install or package these files, but must not redesign the UI by generating a replacement dashboard from shell heredocs.

The immediate migration keeps the existing runtime callbacks/backends while moving visual composition into a stable source-owned shell. Later passes should style or package this source, not replace its structure.
