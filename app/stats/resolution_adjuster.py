from PIL import Image
import os

# Input file name
filename = "C:\\Users\\avask\\Downloads\\WEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE.png"

# Open image
img = Image.open(filename)

# Split file name into name + extension
name, ext = os.path.splitext(filename)

# Save with "_300dpi" appended automatically
output_filename = f"{name}_300dpi{ext}"
img.save(output_filename, dpi=(300, 300))

print(f"Saved as {output_filename} at 300 DPI")