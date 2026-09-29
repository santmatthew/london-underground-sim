#!/bin/bash
# copy the people deliverables from the main tree into the sandbox project (which has its own .godot cache)
P=/home/msant/Projects/Personal/underground-sim
S=$P/build/sandbox_people
mkdir -p $S/assets/people $S/scripts/people $S/scenes/people
rsync -a --exclude='*.glb.import' --exclude='*.res.import' --exclude='*.info.json' --exclude='.godot' $P/assets/people/ $S/assets/people/
rsync -a $P/scripts/people/ $S/scripts/people/
rsync -a $P/scenes/people/ $S/scenes/people/ 2>/dev/null
