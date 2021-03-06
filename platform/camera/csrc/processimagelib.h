#define MMIO_OFFSET_SIZE        4
#define MMIO_TRIBUF_NUM         3
#define MMIO_CAM_NUM            2
#define MMIO_SIZE               MMIO_OFFSET_SIZE*(2+MMIO_CAM_NUM+MMIO_TRIBUF_NUM)

#define MMIO_BASIC_OFFSET       0*MMIO_OFFSET_SIZE
#define MMIO_CMD                MMIO_BASIC_OFFSET+0
    #define CMD_START 5
    #define CMD_STOP 9

#define MMIO_DEBUG_OFFSET       1*MMIO_OFFSET_SIZE
#define MMIO_DEBUG(n)           (MMIO_DEBUG_OFFSET + n)

#define MMIO_CAM_OFFSET(n)      (2+(n))*MMIO_OFFSET_SIZE
#define MMIO_CAM_CMD(n)         MMIO_CAM_OFFSET(n)+0
#define MMIO_CAM_RESP(n)        MMIO_CAM_OFFSET(n)+1
#define MMIO_CAM_RESP_CNT(n)    MMIO_CAM_OFFSET(n)+2

#define MMIO_TRIBUF_OFFSET(n)   (2+MMIO_CAM_NUM+(n))*MMIO_OFFSET_SIZE
#define MMIO_FRAME_BYTES(n)     MMIO_TRIBUF_OFFSET(n)+0
#define MMIO_TRIBUF_ADDR(n)     MMIO_TRIBUF_OFFSET(n)+1


#define CAM_DELAY 0xF0F0
#define CAM_RESET 0x1280

typedef struct {
    uint32_t mmio[MMIO_SIZE];
} Conf;


void write_mmio(volatile Conf* conf, int offset, uint32_t data, int verbose);
uint32_t read_mmio(volatile Conf* conf, int offset, int verbose);
void poll_mmio(volatile Conf* conf, int offset, uint32_t val);

void print_debug_regs(volatile Conf* conf);

// cam_data should contain the cam addr in the lowest byte
uint32_t read_cam_reg(volatile Conf* conf, int camid, uint32_t cam_data);
void write_cam_reg(volatile Conf* conf, int camid, uint32_t cam_data);
void write_cam_safe(volatile Conf* conf, int camid, uint32_t cam_data);


FILE* openImage(char* filename, int* numbytes);
void loadImage(FILE* infile,  volatile void* address, int numbytes);
int saveImage(char* filename,  volatile void* address, int numbytes);


// we don't have a standard library... so reimplement this badly
bool isPowerOf2(unsigned int x);
unsigned int mylog2(unsigned int x);
