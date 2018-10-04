#include "ic_model.h"
#include <stdexcept>

template <class word_t, class mm_word_t, int offset_bits, int idx_bits, int assoc>
ic_blocking_cache_t<word_t,mm_word_t,offset_bits,idx_bits,assoc>::ic_blocking_cache_t(bool verb)
{
  req.valid = false;
  resp.valid = false;
  state = state_ready;

  verbose = verb;

  mm_request_ready = false;
  mm_response.valid = false;

  ic_cache_t<word_t>::linesize = (1<<offset_bits)*sizeof(word_t);
}

template <class word_t, class mm_word_t, int offset_bits, int idx_bits, int assoc>
bool ic_blocking_cache_t<word_t,mm_word_t,offset_bits,idx_bits,assoc>::request_queue_full()
{
  return req.valid; //  || !response_queue_empty();
}

template <class word_t, class mm_word_t, int offset_bits, int idx_bits, int assoc>
bool ic_blocking_cache_t<word_t,mm_word_t,offset_bits,idx_bits,assoc>::response_queue_empty()
{
  return !resp.valid;
}

template <class word_t, class mm_word_t, int offset_bits, int idx_bits, int assoc>
void ic_blocking_cache_t<word_t,mm_word_t,offset_bits,idx_bits,assoc>::request(ic_cpu_cache_request_t<word_t> r)
{
  //if(request_queue_full())
  //  throw std::runtime_error("attempted to request() while request_queue_full()!");

  req = r;
}

template <class word_t, class mm_word_t, int offset_bits, int idx_bits, int assoc>
ic_cpu_cache_response_t<word_t> ic_blocking_cache_t<word_t,mm_word_t,offset_bits,idx_bits,assoc>::peek_response()
{
  return resp;
}

template <class word_t, class mm_word_t, int offset_bits, int idx_bits, int assoc>
void ic_blocking_cache_t<word_t,mm_word_t,offset_bits,idx_bits,assoc>::dequeue_response()
{
  if(response_queue_empty())
    throw std::runtime_error("attempted to get_response() while response_queue_empty!");

  resp.valid = false;
}

template <class word_t, class mm_word_t, int offset_bits, int idx_bits, int assoc>
void ic_blocking_cache_t<word_t,mm_word_t,offset_bits,idx_bits,assoc>::tick()
{
  if (mm_request.valid && mm_request_ready)
  {
    if (state == state_writeback)
    {
      if (writeback_pos == nwords-1)
        state = state_refill;
      writeback_pos++;
    }
    else if (state == state_refill)
      refill_request_pos++;
  }

  resp.valid = false;
  mm_request.valid = false;

  int word_offset_bits = log2i(sizeof(word_t));
  int offset = (req.addr >> word_offset_bits) & ((1<<offset_bits)-1);
  int idx = (req.addr >> (word_offset_bits + offset_bits)) & ((1<<idx_bits)-1);
  int tag = req.addr >> (word_offset_bits+offset_bits+idx_bits);
  bool tag_match[assoc];
  bool hit = false;
  for(int i = 0; i < assoc; i++)
    hit |= tag_match[i] = sets[idx].lines[i].valid && sets[idx].lines[i].tag == tag;

  ic_cache_t<word_t>::num_stores += req.type == op_st && state == state_ready;
  ic_cache_t<word_t>::num_loads  += req.type == op_ld && state == state_ready;
  ic_cache_t<word_t>::num_store_hits += req.type == op_st && hit && state == state_ready;
  ic_cache_t<word_t>::num_load_hits  += req.type == op_ld && hit && state == state_ready;
  ic_cache_t<word_t>::num_writebacks += req.valid && !hit && state == state_ready && sets[idx].lines[sets[idx].repl_bits].dirty;
  ic_cache_t<word_t>::num_cycles_blocked += req.valid;

  if(state == state_ready || state == state_resolve_miss)
  {
    if (verbose)
      printf("ic_tick() : state == %s\n", state == state_ready ? "ready" : "resolve_miss");
    for(int i = 0; i < assoc; i++)
    {
      if(tag_match[i] && req.valid)
      {
        if(req.valid && req.type == op_st)
        {
          sets[idx].lines[i].dirty = true;
          ((word_t*)&sets[idx].lines[i].data)[offset] = req.data;
        }
        else if(req.valid)
        {
          if(req.type != op_ld)
            throw std::runtime_error("I got a non-ld/st/nop request!");

          resp.valid = true;
          resp.type = req.type;
          if (verbose)
            printf("ic_tick() : satisfying load request : addr = %x : idx = %d : line = %d : offset = %d\n", req.addr, idx, i, offset);
          resp.data = ((word_t*)&sets[idx].lines[i].data)[offset];
          if (verbose)
            printf("ic_tick() : response : data=%08x\n", *(uint32_t*)&resp.data);
          resp.tag = req.tag;
        }

        req.valid = false;
        ic_cache_t<word_t>::num_cycles_blocked --;
      }
    }

    state = !req.valid || hit ? state_ready : (sets[idx].lines[sets[idx].repl_bits].dirty ? state_writeback : state_refill);

    r_req = req;
    writeback_pos = 0;
    refill_request_pos = 0;
    refill_response_pos = 0;
  }
  else if(state == state_writeback)
  {
    int idx_writeback = (r_req.addr >> (word_offset_bits + offset_bits)) & ((1<<idx_bits)-1);

    mm_request.valid = (writeback_pos != nwords);
    mm_request.type = op_st;
    mm_request.addr = (r_req.addr & ~((1 << (word_offset_bits+offset_bits))-1)) + (writeback_pos * access_port_width * sizeof(word_t));
    mm_request.addr = (((sets[idx_writeback].lines[sets[idx_writeback].repl_bits].tag << idx_bits) + idx_writeback) << (word_offset_bits+offset_bits)) + (writeback_pos * access_port_width * sizeof(word_t));
    mm_request.tag = 0;
    mm_request.data = sets[idx_writeback].lines[sets[idx_writeback].repl_bits].data[writeback_pos];
  }
  else if(state == state_refill)
  {
    int idx_refill = (r_req.addr >> (word_offset_bits + offset_bits)) & ((1<<idx_bits)-1);
    int tag_refill = r_req.addr >> (word_offset_bits+offset_bits+idx_bits);

    mm_request.valid = (refill_request_pos == 0);
    mm_request.type = op_ld;
    mm_request.addr = (r_req.addr & ~((1 << (word_offset_bits+offset_bits))-1));

    if (verbose && mm_request.valid)
      printf("ic_tick() : mm_request.addr == %08x\n", mm_request.addr);

    mm_request.tag = 0;

    if(mm_response.valid && mm_response.type == op_ld)
    {
      unsigned int* ptr = (unsigned int*)&mm_response.data;
      if (verbose)
        printf("ic_tick() : idx = %d : mm_response.valid : refill_response_pos == %d : data=%08x%08x%08x%08x\n", idx_refill, refill_response_pos, ptr[3], ptr[2], ptr[1], ptr[0]);

      sets[idx_refill].lines[sets[idx_refill].repl_bits].data[refill_response_pos] = mm_response.data;

      if(refill_response_pos == nwords-1)
      {
        sets[idx_refill].lines[sets[idx_refill].repl_bits].tag = tag_refill;
        sets[idx_refill].lines[sets[idx_refill].repl_bits].dirty = false;
        sets[idx_refill].lines[sets[idx_refill].repl_bits].valid = true;
        sets[idx_refill].repl_bits = (sets[idx_refill].repl_bits+1) % assoc;
        state = state_resolve_miss;
      }

      refill_response_pos++;
    }
  }
}
