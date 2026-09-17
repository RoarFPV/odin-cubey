package cubey

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:container/queue"

TRACY_ENABLE :: #config(TRACY_ENABLE, false)
import tracy "lib/odin-tracy"

tracy :: tracy

print_file_info :: proc(fi: os.File_Info) {
	// Split the path into directory and filename
	_, filename := filepath.split(fi.fullpath)

	SIZE_WIDTH :: 12
	buf: [SIZE_WIDTH]u8

	// Print size to string backed by buf on stack, no need to free
	_size := "-" if fi.type == os.File_Type.Directory else fmt.bprintf(buf[:], "%v", fi.size)

	// Right-justify size for display, heap allocated
	size := strings.right_justify(_size, SIZE_WIDTH, " ")
	defer delete(size)

	if fi.type == os.File_Type.Directory {
		fmt.printf("%v [%v]\n", size, filename)
	} else {
		fmt.printf("%v %v\n", size, filename)
	}
}

sys_find_files :: proc(dirname:string, filter:string, found:^[dynamic]string, allocator := context.allocator) {
	// fmt.println("Listing: ", dirname)

  infos := queue.Queue(os.File_Info){}
  alloc := context.allocator
  queue.init(&infos, 128, alloc)
  defer queue.destroy(&infos)

  fi, err := os.stat(dirname, alloc)

  if err != os.ERROR_NONE {
    return
  }

  queue.push_back(&infos, fi)


  for queue.len(infos) > 0 {

    info := queue.pop_front(&infos)
    
    if info.type == .Directory {
      fis: []os.File_Info
      // defer os.file_info_slice_delete(fis) // fis is a slice, we need to remember to free it
      
      f, err := os.open(info.fullpath)
      defer os.close(f)

      if err != os.ERROR_NONE {
        continue
      }
      
      fis, err = os.read_dir(f, -1, allocator) // -1 reads all file infos
      if err != os.ERROR_NONE {
        fmt.eprintln("Could not read directory", err)
        continue
      }

      for fi in fis {
        queue.push_back(&infos, fi)
      }
    }
    else
    {
      if strings.contains(info.fullpath, filter) {
        append(found, info.fullpath)
      }
    } 

    // print_file_info(info)
    
  }
}