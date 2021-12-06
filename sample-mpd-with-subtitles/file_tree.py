#需要检查一个“目录”，或者某个包含子目录的目录树，并根据某种模式迭代所有的文件（也可能包含子目录）使用的是os.walk生成器
from xml.dom.minidom import parse
import xml.dom.minidom
import os, fnmatch

def split_file(path, name, start, size, new_file_name):
    inputfile = open(os.path.join(path,name),'rb')
    if not inputfile:
        printf("inputfile failed! %s" % os.path.join(path,name))
    inputfile.seek(start, 0)
    data = inputfile.read(size)
    if not data:
        printf("read failed! %d" % size)
    filename = os.path.join(path, name.replace(".", "_"))
    filename = os.path.join(filename, new_file_name)

    (filepath, tempfilename) = os.path.split(filename)
    isExists=os.path.exists(filepath)
    if not isExists:
        os.makedirs(filepath) 

    fileobj = open(filename,'wb')
    if not data:
        printf("open failed! %s" % filename)
    fileobj.write(data)
    fileobj.close()
    inputfile.close()

def parse_seglist(path, name):
    DOMTree = xml.dom.minidom.parse(os.path.join(path,name))
    seglist = DOMTree.documentElement
    files = seglist.getElementsByTagName("file")
    for file in files:
        print ("*****file*****")
        ref_str = file.getAttribute("ref")
        #ref_str = ref_str.replace("/", "\\")
        print ("ref: %s" % file.getAttribute("ref"))
        size = file.getElementsByTagName('size')[0]
        size_str = size.childNodes[0].data
        print ("Type: %s" % size_str)
        start = file.getElementsByTagName('start')[0]
        start_str = start.childNodes[0].data
        print ("Format: %s" % start_str)
        video = file.getElementsByTagName('video')[0]
        video_str = video.childNodes[0].data
        print ("video: %s" % video_str)
        split_file(path, video_str, int(start_str), int(size_str), ref_str)


def deal_mpd(filename):
    mpdfile = open(filename, "r")
    data = mpdfile.read()
    mpdfile.close()
    new_mdpfile = open(filename.replace(".mpd","_new.mpd"), "w+")
    data = data.replace(".fmp4", "_fmp4")
    data = data.replace("segment_server_invalid_profile/segment_server.php?sid={SESSION_ID}&amp;url=", "")
    data = data.replace("segment_server_invalid_profile/subtitle_segment_server.php?sid={SESSION_ID}&amp;url=", "")
    data = data.replace("segment_server_valid_profile/segment_server.php?sid={SESSION_ID}&amp;url=", "")
    data = data.replace("segment_server_valid_profile/subtitle_segment_server.php?sid={SESSION_ID}&amp;url=", "")
    new_mdpfile.write(data)
    mpdfile.close()
    

def all_files(root):
    for path, subdirs, files in os.walk(root):
        files.sort()
        for name in files:
            if fnmatch.fnmatch(name, 'seglist.xml'):
                parse_seglist(path, name)
                yield os.path.join(path,name)
            if fnmatch.fnmatch(name, '*.mpd'):
                deal_mpd(os.path.join(path,name))
                yield os.path.join(path,name)




if __name__ == '__main__':
    for path in all_files('.'):
        print (path)
