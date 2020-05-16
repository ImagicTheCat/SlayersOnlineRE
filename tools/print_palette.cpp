// Program to print the first indexed color of a PNG's palette as "R G B" (8-bit integers) or
// nothing if not indexed / on error.
// compile: g++ print_palette.cpp -o print_palette -lpng
// params: <file path>

#include <iostream>
#include <cstdio>
#include <png.h>

int main(int argc, char **argv)
{
  if(argc < 2){
    std::cerr << "missing file path" << std::endl;
    return 1;
  }

  FILE *fp = fopen(argv[1], "rb");
  if(!fp){
    std::cerr << "couldn't open file" << std::endl;
    return 1;
  }

  unsigned char header[8];
  fread(header, 1, 8, fp);
  if(png_sig_cmp(header, 0, 8) != 0){
    std::cerr << "invalid PNG file" << std::endl;
    return 1;
  }

  png_structp png_ptr = png_create_read_struct
    (PNG_LIBPNG_VER_STRING, (png_voidp)NULL,
     NULL, NULL);
  if(!png_ptr)
    return 1;

  png_infop info_ptr = png_create_info_struct(png_ptr);
  if(!info_ptr)
  {
    png_destroy_read_struct(&png_ptr,
        (png_infopp)NULL, (png_infopp)NULL);
    return 1;
  }

  png_infop end_info = png_create_info_struct(png_ptr);
  if(!end_info)
  {
    png_destroy_read_struct(&png_ptr, &info_ptr,
        (png_infopp)NULL);
    return 1;
  }

  if(setjmp(png_jmpbuf(png_ptr)))
  {
    png_destroy_read_struct(&png_ptr, &info_ptr,
        &end_info);
    fclose(fp);
    return 1;
  }

  png_init_io(png_ptr, fp);
  png_set_sig_bytes(png_ptr, 8);
  png_read_png(png_ptr, info_ptr, PNG_TRANSFORM_IDENTITY, NULL);
  int num_palette;
  png_colorp palette;
  png_get_PLTE(png_ptr, info_ptr, &palette, &num_palette);
  if(num_palette > 0)
    std::cout << (size_t)palette[0].red << " " << (size_t)palette[0].green << " " << (size_t)palette[0].blue << std::endl;
  png_destroy_read_struct(&png_ptr, &info_ptr, &end_info);

  return 0;
}
