#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct{unsigned int addr; unsigned int burst;} Transaction;

typedef struct{int front; int rear; int itemCount; unsigned char* data; unsigned int dataBytes;} Queue;

const unsigned int QUEUE_MAX = 1024*1024;

unsigned char* QPeek(Queue* q) {
  return q->data+(q->front*q->dataBytes);
}

//bool isEmpty() {
//  return itemCount == 0;
//}

bool QFull(Queue* q) {
  return q->itemCount == QUEUE_MAX;
}

int QSize(Queue* q) {
  return q->itemCount;
}

void QPush(Queue* q, unsigned char* data) {

  if(!QFull(q)) {

    if(q->rear == QUEUE_MAX-1) {
      q->rear = -1;
    }

    //intArray[++rear] = data;
    q->rear++;
    memcpy(q->data+(q->rear*q->dataBytes), data, q->dataBytes);
    q->itemCount++;
  }else{
    printf("Q is full!\n");
    exit(1);
  }
}

unsigned char* QPop(Queue* q) {
  //int data = intArray[front++];
  unsigned char* data = q->data+(q->front*q->dataBytes);
  q->front++;

  if(q->front == QUEUE_MAX) {
    q->front = 0;
  }

  q->itemCount--;
  return data;
}

void QInit(Queue* q, unsigned int dataBytes){
  q->front=0;
  q->rear=-1;
  q->itemCount=0;
  q->dataBytes = dataBytes;
  q->data = (unsigned char*)malloc(QUEUE_MAX*dataBytes);
}

//unsigned int MEMBASE = 0x30008000;
//unsigned int MEMSIZE = 8192*2;
//unsigned char* memory;

const unsigned int PORTS = 4;
//std::queue<Transaction> readQ[PORTS];
//std::queue<Transaction> writeQ[PORTS];
Queue readQ[PORTS];
Queue writeQ[PORTS];

unsigned int masterBytesRead[PORTS];
unsigned int masterBytesWritten[PORTS];

unsigned int cyclesSinceWrite[PORTS];

float randf(){ return (float)rand()/(float)(RAND_MAX); }

unsigned int bytesRead(){
  unsigned int b = 0;
  for(int i=0; i<PORTS; i++){
    b+=masterBytesRead[i];
  }
  return b;
}

unsigned int bytesWritten(){
  unsigned int b = 0;
  for(int i=0; i<PORTS; i++){
    b+=masterBytesWritten[i];
  }
  return b;
}

void init(){
  for(int i=0; i<PORTS; i++){
    QInit(&readQ[i], sizeof(Transaction));
    QInit(&writeQ[i], sizeof(Transaction));
  }

  for(int i=0; i<PORTS; i++){
    masterBytesRead[i]=0;
    masterBytesWritten[i]=0;
    cyclesSinceWrite[i]=0;
  }
}
  
void printSlave(
  int id,
  unsigned char* IP_CLK,
  unsigned char* IP_ARESET_N,
  unsigned int* ARADDR,
  unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned int* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* RRESP,
  unsigned char* WVALID,
  unsigned char* WREADY){

  printf("----------------------\n");
  printf("IP_CLK(in): %d\n",(int)*IP_CLK);
  printf("IP_ARESET_N(in): %d\n",(int)*IP_ARESET_N);
  printf("S_ARADDR(in): %d/%#x\n",*ARADDR, *ARADDR);
  printf("S_ARVALID(in): %d\n",(int)*ARVALID);
  printf("S_ARREADY(out): %d\n",(int)*ARREADY);
  printf("S_AWADDR(in): %d/%#x\n", *AWADDR, *AWADDR );
  printf("S_AWVALID(in): %d\n",(int)*AWVALID);
  printf("S_AWREADY(out): %d\n",(int)*AWREADY);
  printf("S_RDATA(out): %d\n",*RDATA);
  printf("S_RVALID(out): %d\n",(int)*RVALID);
  printf("S_RREADY(in): %d\n",(int)*RREADY);
  printf("S_BRESP(out): %d\n",(int)*BRESP);
  printf("S_BVALID(out): %d\n",(int)*BVALID);
  printf("S_WVALID(in): %d\n",(int)*WVALID);
  printf("S_WREADY(out): %d\n",(int)*WREADY);
}

void resetSlave(
  int id,
  unsigned char* IP_CLK,
  unsigned char* IP_ARESET_N,
  unsigned int* ARADDR,
  unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned int* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* RRESP,
  unsigned char* WVALID,
  unsigned char* WREADY){

  *AWVALID = false;
  *ARVALID = false;
  *BREADY = true;
  *RREADY = true;
}

bool checkSlaveWriteResponse(
  int id,
  unsigned char* IP_CLK,
  unsigned char* IP_ARESET_N,
  unsigned int* ARADDR,
  unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned int* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* RRESP,
  unsigned char* WVALID,
  unsigned char* WREADY){

  if( *BVALID && *BRESP==2){
    printf("Slave %d Error", id);
    exit(1);
  }else if( *BVALID && *BRESP==0){
    return true;
  }else if( *BVALID ){
    printf("Slave %d returned strange respose? ", *BRESP);
    exit(1);
  }

  return false;
}

bool checkSlaveReadResponse(
  int id,
  unsigned char* IP_CLK,
  unsigned char* IP_ARESET_N,
  unsigned int* ARADDR,
  unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned int* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* RRESP,
  unsigned char* WVALID,
  unsigned char* WREADY,
  unsigned int* dataOut){

  if( *RVALID && *RRESP==2){
    printf("Slave %d read Error", id);
    exit(1);
  }else if( *RVALID && *RRESP==0){
    *dataOut = *RDATA;
    return true;
  }else if( *RVALID ){
    printf("Slave %d returned strange respose? ", *RRESP);
    exit(1);
  }

  return false;
}

bool slaveReadReq(
  unsigned int address,
  int id,
  unsigned char* IP_CLK,
  unsigned char* IP_ARESET_N,
  unsigned int* ARADDR,
  unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned int* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* RRESP,
  unsigned char* WVALID,
  unsigned char* WREADY){

  //  if(*ARREADY==false){
  //    printf("IP_SAXI0_ARREADY should be true\n");
  //    exit(1);
  //  }
  
  *ARVALID = true;
  *ARADDR = address;

  return *ARREADY;
}

void activateMasterRead(
  int port,
  const unsigned int* ARADDR,
  const unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned long* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* RRESP,
  unsigned char* RLAST,
  unsigned char* ARLEN,
  unsigned char* ARSIZE,
  unsigned char* ARBURST){

  *ARREADY = true;
  *RREADY = true;
}

void activateMasterWrite(
  int id,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned long* WDATA,
  unsigned char* WVALID,
  unsigned char* WREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* WSTRB,
  unsigned char* WLAST,
  unsigned char* AWLEN,
  unsigned char* AWSIZE,
  unsigned char* AWBURST){

  *AWREADY = true;
  *WREADY = true;
  *BREADY = true;
}

void deactivateMasterRead(
  int port,
  const unsigned int* ARADDR,
  const unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned long* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* RRESP,
  unsigned char* RLAST,
  unsigned char* ARLEN,
  unsigned char* ARSIZE,
  unsigned char* ARBURST){

  *ARREADY = false;
  *RREADY = false;
}

void deactivateMasterWrite(
  int id,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned long* WDATA,
  unsigned char* WVALID,
  unsigned char* WREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* WSTRB,
  unsigned char* WLAST,
  unsigned char* AWLEN,
  unsigned char* AWSIZE,
  unsigned char* AWBURST){

  *AWREADY = false;
  *WREADY = false;
  *BREADY = false;
}

void printMasterRead(
  int id,
  const unsigned int* ARADDR,
  const unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned long* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* RRESP,
  unsigned char* RLAST,
  unsigned char* ARLEN,
  unsigned char* ARSIZE,
  unsigned char* ARBURST){

  printf("----------------------\n");
  //printf("IP_CLK(in): " << (int)IP_CLK);
  //printf("IP_ARESET_N(in): " << (int)IP_ARESET_N);
  printf("M%d_ARADDR(out): %d/%#x\n",id,*ARADDR,*ARADDR);
  printf("M%d_ARVALID(out): %d\n",id, (int)*ARVALID);
  printf("M%d_ARREADY(in): %d\n",id, (int)*ARREADY);
}

void printMasterWrite(
  int id,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned long* WDATA,
  unsigned char* WVALID,
  unsigned char* WREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* WSTRB,
  unsigned char* WLAST,
  unsigned char* AWLEN,
  unsigned char* AWSIZE,
  unsigned char* AWBURST){

  printf("----------------------\n");
  printf("M%d_AWADDR(out): %d/%#x\n",id, *AWADDR, *AWADDR);
  printf("M%d_AWVALID(out): %d\n",id,(int)*AWVALID);
  printf("M%d_AWREADY(in): %d\n",id, (int)*AWREADY);
  
  printf("M%d_WDATA(out): %d/%#x\n",id, *WDATA, *WDATA);
  printf("M%d_WVALID(out): %d\n",id, (int)*WVALID);
  printf("M%d_WREADY(in): %d\n",id, (int)*WREADY);
}

// return data to master
void masterReadData(
  bool verbose,
  unsigned char* memory,
  int port,
  const unsigned int* ARADDR,
  const unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned long* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* RRESP,
  unsigned char* RLAST,
  unsigned char* ARLEN,
  unsigned char* ARSIZE,
  unsigned char* ARBURST){

  if( QSize(&readQ[port])>0 && *RREADY){
    if(false && randf()>0.2f){
      *RVALID = false;
    }else{
      Transaction* t = (Transaction*)QPeek(&readQ[port]);
      
      *RDATA = *(unsigned long*)(&memory[t->addr]);
      *RVALID = true;
      
      if(verbose){
        printf("MAXI%d Service Read Addr:%d data:%d remaining_burst:%d outstanding_requests:%d\n", port, t->addr, *RDATA, t->burst, QSize(&readQ[port]));
      }
      
      t->burst--;
      t->addr+=8;

      masterBytesRead[port] += 8; // for debug
      
      if(t->burst==0){
        QPop(&readQ[port]);
      }
    }
  }else if( QSize(&readQ[port]) >0 && *RREADY==false){
    if(verbose){printf("MAXI%d: %d outstanding read requests, but IP isn't ready\n", port, QSize(&readQ[port]) );}
  }else{
    if(verbose){printf("MAXI%d no outstanding read requests\n",port);}
    *RVALID = false;
  }
}

// service read requests from master
void masterReadReq(
  bool verbose,
  unsigned int MEMBASE,
  unsigned int MEMSIZE,
  int port,
  const unsigned int* ARADDR,
  const unsigned char* ARVALID,
  unsigned char* ARREADY,
  unsigned long* RDATA,
  unsigned char* RVALID,
  unsigned char* RREADY,
  unsigned char* RRESP,
  unsigned char* RLAST,
  unsigned char* ARLEN,
  unsigned char* ARSIZE,
  unsigned char* ARBURST){

  if(*ARVALID){
    // read request
    Transaction t;
    assert(*ARSIZE==3);
    assert(*ARBURST==1);
    t.addr = *ARADDR;
    t.burst = *ARLEN+1;

    if(verbose){
      printf("MAXI%d Read Request addr:%d/%#x (base rel):%d/%#x burst:%d\n", port, t.addr, t.addr, (t.addr-MEMBASE), (t.addr-MEMBASE), t.burst );
      //std::cout << "MAXI" << port << " Read Request addr (base rel):" << (t.addr-MEMBASE) << "/" << std::hex << "0x" << (t.addr-MEMBASE) << std::dec << " burst:" << t.burst << std::endl;
    }
    
    t.addr -= MEMBASE;

    if(t.addr>=MEMSIZE){
      printf("Segmentation fault on read! Attempted to read address %#x, which is outside of range [%#x,%#x]\n", *ARADDR, MEMBASE, MEMBASE+MEMSIZE);
      exit(1);
    }
    
    QPush(&readQ[port],(unsigned char*)&t);
  }else{
    if(verbose){ printf("MAXI%d no read request!\n",port);}
  }
}

// return data to master
void masterWriteData(
  bool verbose,
  unsigned char* memory,
  int port,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned long* WDATA,
  unsigned char* WVALID,
  unsigned char* WREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* WSTRB,
  unsigned char* WLAST,
  unsigned char* AWLEN,
  unsigned char* AWSIZE,
  unsigned char* AWBURST){

  assert(*WREADY); // we drive this... should always be true

  *BVALID = 0;
  
  if( QSize(&writeQ[port])>0 && *WVALID ){
    Transaction* t = (Transaction*)QPeek(&writeQ[port]);

    *(unsigned long*)(&memory[t->addr]) = *WDATA;

    if(verbose){
      //std::cout << "MAXI" << port << " Accept Write, Addr: " << t.addr << "/" << std::hex << "0x" << std::dec << t.addr << " data: " << WDATA << " remaining_burst: " << t.burst << " outstanding_requests: " << writeQ[port].size() << std::endl;
      printf("MAXI%d Accept Write, Addr: %d/%#x data: %d remaining_burst: %d outstanding_requests: %d\n", port, t->addr, t->addr, *WDATA, t->burst, QSize(&writeQ[port]) );
    }
    
    t->burst--;
    t->addr+=8;

    masterBytesWritten[port] += 8; // for debug
          
    if(t->burst==0){
      QPop(&writeQ[port]);
      *BVALID = 1;
      *BRESP = 0;

      if(*BREADY==0){
        printf("MAXI%d NYI - BREADY is false\n");
        exit(1);
      }
    }

    cyclesSinceWrite[port] = 0;
  }else if( QSize(&writeQ[port])<=0 && *WVALID ){
    printf("Error: attempted to write data, but there was no outstanding write addresses! (master port %d)\n",port);
    exit(1);
  }else{
    if(verbose){ printf("MAXI%d no write data (%d outstanding requests)\n",port,QSize(&writeQ[port]));}

    cyclesSinceWrite[port]++;

    if( cyclesSinceWrite[port]>200000 && QSize(&writeQ[port])>0 ){
      Transaction* t = (Transaction*)QPeek(&writeQ[port]);
      printf("MAXI%d write port is stalled out? No data sent for %d cycles (%d outstanding write requests, top addr %d)\n",port,cyclesSinceWrite[port],QSize(&writeQ[port]),t->addr);
      exit(1);
    }
  }
}

void masterWriteReq(
  bool verbose,
  unsigned int MEMBASE,
  unsigned int MEMSIZE,
  int port,
  unsigned int* AWADDR,
  unsigned char* AWVALID,
  unsigned char* AWREADY,
  unsigned long* WDATA,
  unsigned char* WVALID,
  unsigned char* WREADY,
  unsigned char* BRESP,
  unsigned char* BVALID,
  unsigned char* BREADY,
  unsigned char* WSTRB,
  unsigned char* WLAST,
  unsigned char* AWLEN,
  unsigned char* AWSIZE,
  unsigned char* AWBURST){

  if(*AWVALID){
    assert(*AWSIZE==3);
    assert(*AWBURST==1);
    assert(*WSTRB==255);
    
    Transaction t;
    t.addr = *AWADDR;
    t.burst = *AWLEN+1;

    if(verbose){
      printf("MAXI%d Write Request addr:%d/%#x (base rel):%d/%#x burst:%d\n", port, t.addr, t.addr, (t.addr-MEMBASE), (t.addr-MEMBASE), t.burst);
    }
    
    t.addr -= MEMBASE;

    if(t.addr>=MEMSIZE){
      printf("MAXI%d Segmentation fault on write!\n",port);
      exit(1);
    }

    //writeQ[port].push(t);
    QPush(&writeQ[port],(unsigned char*)&t);
  }
}

void loadFile( char* filename, unsigned char* memory, unsigned int addrOffset ){
  FILE* infile = fopen(filename,"rb");
  if(infile==NULL){printf("could not open input '%s'\n", filename);}
  fseek(infile, 0L, SEEK_END);
  unsigned long insize = ftell(infile);
  fseek(infile, 0L, SEEK_SET);
  fread( memory+addrOffset, insize, 1, infile );
  fclose( infile );
  
  //std::cout << "Input File " << inputCount << ": filename=" << argv[curArg] << " address=0x" << std::hex << addr << " addressOffset=0x" << addrOffset << std::dec << " bytes=" << insize <<std::endl;
  printf("Input File: filename=%s addressOffset=0x%x bytes=%d\n",filename,addrOffset,insize);
}

void saveFile( const char* filename, unsigned char* memory, unsigned int addrOffset, unsigned int bytes ){
  FILE* outfile = fopen( filename, "wb" );
  if(outfile==NULL){printf("could not open output '%s'\n", filename );}
  fwrite( memory+addrOffset, bytes, 1, outfile);
  fclose(outfile);

  //std::cout << "Output File " << outputCount << ": filename=" << outFilename << " address=0x" << std::hex << addr << " addressOffset=0x" << addrOffset << std::dec << " W=" << w <<" H="<<h<<" bitsPerPixel="<<bitsPerPixel<<" bytes="<<bytes<<std::endl;
  printf("Output File: filename=%s addressOffset=0x%x bytes=%d\n",filename,addrOffset,bytes);
}

bool checkPorts(){
  bool errored = false;
  
  for(int port=0; port<PORTS; port++){
    if( QSize(&readQ[port])>0){
      //std::cout << "MAXI" << port << " Error, outstanding read requests at end of time! cnt:" << readQ[port].size() << " bytesRead: " << masterBytesRead[port] << std::endl;
      printf("MAXI%d Error, outstanding read requests at end of time! cnt:%d bytesRead: %d\n", port, QSize(&readQ[port]), masterBytesRead[port] );
      errored = true;
    }
    
    if( QSize(&writeQ[port])>0){
      //std::cout << "MAXI" << port << " Error, outstanding write requests at end of time! cnt:" << writeQ[port].size() << " bytesWritten: " << masterBytesWritten[port] << std::endl;
      printf("MAXI%d Error, outstanding write requests at end of time! cnt:%d bytesWritten:%d\n",port, QSize(&writeQ[port]),masterBytesWritten[port] );
      errored = true;
    }
  }

  return errored;
}
