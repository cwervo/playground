import os
import shutil

src_base = "/Users/cwervo/code/folk/vendor/apriltag"
dest_base = "/Users/cwervo/code/playground/folk_ios/FolkApp/apriltag"

os.makedirs(dest_base, exist_ok=True)
os.makedirs(os.path.join(dest_base, "common"), exist_ok=True)

files_to_copy = [
    "apriltag.c", "apriltag.h", "apriltag_pose.c", "apriltag_pose.h",
    "apriltag_quad_thresh.c", "apriltag_math.h",
    "tag36h11.c", "tag36h11.h", "tagStandard52h13.c", "tagStandard52h13.h"
]

for f in files_to_copy:
    shutil.copy2(os.path.join(src_base, f), os.path.join(dest_base, f))

# Copy everything in common/
src_common = os.path.join(src_base, "common")
dest_common = os.path.join(dest_base, "common")
for f in os.listdir(src_common):
    if f.endswith(".c") or f.endswith(".h"):
        shutil.copy2(os.path.join(src_common, f), os.path.join(dest_common, f))

print("AprilTag library copied successfully!")
