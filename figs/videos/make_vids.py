import subprocess
import os

fig_folder = "frames"
vid_folder = "videos"
for fname in os.listdir(fig_folder):
    #command = 'ffmpeg -r 1 -f image2 -s 1920x1080 -i ' + fig_folder + '/' + fname + '/' + 'n%d.png -vcodec libx264 -crf 20  -pix_fmt yuv420p ' + vid_folder + '/' + fname + '.mp4'
    command = 'ffmpeg -r 1 -f image2 -s 1920x1080 -i ' + fig_folder + '/' + fname + '/' + fname + '_n%d.png -vcodec libx264 -crf 20  -pix_fmt yuv420p ' + vid_folder + '/' + fname + '.mp4'
    subprocess.call(command, shell=True)