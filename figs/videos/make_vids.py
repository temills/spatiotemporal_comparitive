import subprocess
import os

# fig_folder = "monkey_kid_lin/frames"
# vid_folder = "monkey_kid_lin/videos"
# for fname in os.listdir(fig_folder):
#     #command = 'ffmpeg -r 1 -f image2 -s 1920x1080 -i ' + fig_folder + '/' + fname + '/' + 'n%d.png -vcodec libx264 -crf 20  -pix_fmt yuv420p ' + vid_folder + '/' + fname + '.mp4'
#     command = 'ffmpeg -r 1 -f image2 -s 1920x1080 -i ' + fig_folder + '/' + fname + '/' + fname + '_n%d.png -vcodec libx264 -crf 20  -pix_fmt yuv420p ' + vid_folder + '/' + fname + '.mp4'
#     subprocess.call(command, shell=True)


fig_dir = "overlaid/frames/"
vid_dir = "overlaid/videos/"
for pair_dir in os.listdir(fig_dir):
    path = fig_dir + pair_dir + '/'
    if (not os.path.exists(vid_dir + pair_dir)):
        os.mkdir(vid_dir + pair_dir)
    for fname in os.listdir(path):
        if (not os.path.exists(vid_dir + pair_dir + '/' +fname + '.mp4')):
            #command = 'ffmpeg -r 1 -f image2 -s 1920x1080 -i ' + fig_folder + '/' + fname + '/' + 'n%d.png -vcodec libx264 -crf 20  -pix_fmt yuv420p ' + vid_folder + '/' + fname + '.mp4'
            command = 'ffmpeg -r 2.5 -f image2 -s 1920x1080 -i ' + path + fname + '/' + '%d.png -vcodec libx264 -crf 20  -pix_fmt yuv420p ' + vid_dir + pair_dir + '/' + fname + '.mp4'
            subprocess.call(command, shell=True)
        