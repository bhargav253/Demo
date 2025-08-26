#!/usr/bin/env python3

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge, Timer, ClockCycles, Join, First, Event
from cocotb.queue import Queue
import random
import asyncio
from collections import deque

class FIFOMonitor:
    """Central monitor that tracks expected FIFO state"""
    def __init__(self, depth=16):
        self.expected_queue = deque()
        self.depth = depth
        self.write_count = 0
        self.read_count = 0
        self.data_verified = 0
        self.errors = 0
        self.lock = asyncio.Lock()
        self.data_ready_event = Event()
        
    async def add_write_transaction(self, data):
        """Add a write transaction to expected queue"""
        async with self.lock:
            if len(self.expected_queue) < self.depth:
                self.expected_queue.append(data)
                self.write_count += 1
                self.data_ready_event.set()
                return True
            return False
            
    async def add_read_transaction(self):
        """Get and remove a read transaction from expected queue"""
        async with self.lock:
            if self.expected_queue:
                data = self.expected_queue.popleft()
                self.read_count += 1
                if len(self.expected_queue) == 0:
                    self.data_ready_event.clear()
                return data
            return None
            
    async def verify_read_data(self, actual_data):
        """Verify read data matches expected data"""
        async with self.lock:
            if not self.expected_queue:
                self.errors += 1
                cocotb.log.error(f"Read verification failed: Expected data but queue is empty")
                return False
                
            expected_data = self.expected_queue.popleft()
            self.read_count += 1
            self.data_verified += 1
            
            if actual_data != expected_data:
                self.errors += 1
                cocotb.log.error(f"Data mismatch: Expected {expected_data}, Got {actual_data}")
                return False
                
            if len(self.expected_queue) == 0:
                self.data_ready_event.clear()
                
            return True
            
    def get_status(self):
        """Get current FIFO status"""
        return {
            'count': len(self.expected_queue),
            'empty': len(self.expected_queue) == 0,
            'full': len(self.expected_queue) == self.depth,
            'almost_empty': len(self.expected_queue) <= 1,
            'almost_full': len(self.expected_queue) >= self.depth - 1,
            'write_count': self.write_count,
            'read_count': self.read_count,
            'data_verified': self.data_verified,
            'errors': self.errors
        }

class FIFOTestbench:
    def __init__(self, dut, monitor):
        self.dut = dut
        self.clock = dut.clk
        self.reset = dut.rst_n
        self.monitor = monitor
        
    async def reset_dut(self):
        self.dut.rst_n.value = 0
        self.dut.psh.value = 0
        self.dut.pop.value = 0
        self.dut.din.value = 0
        await ClockCycles(self.clock, 2)
        self.dut.rst_n.value = 1
        await RisingEdge(self.clock)
        
    async def write_data(self, data):
        """Write data to FIFO and update monitor"""
        if self.dut.full.value == 1:
            return False
            
        self.dut.psh.value = 1
        self.dut.din.value = data
        await RisingEdge(self.clock)
        self.dut.psh.value = 0
        
        # Update monitor
        success = await self.monitor.add_write_transaction(data)
        if not success:
            cocotb.log.warning(f"Monitor rejected write data {data} - queue full")
            
        return success
        
    async def read_data(self):
        """Read data from FIFO and verify with monitor"""
        if self.dut.dout_val.value == 0:
            return None
            
        self.dut.pop.value = 1
        await RisingEdge(self.clock)
        data = self.dut.dout.value.integer
        self.dut.pop.value = 0
        
        # Verify with monitor
        await self.monitor.verify_read_data(data)
        
        return data

async def writer_coroutine(tb, num_transactions=100, max_delay=10):
    """Parallel writer coroutine that writes data to FIFO"""
    cocotb.log.info("Writer coroutine started")
    
    for i in range(num_transactions):
        # Random delay between writes
        delay = random.randint(1, max_delay)
        await ClockCycles(tb.clock, delay)
        
        # Generate random data
        data = random.randint(0, 255)
        
        # Write data if FIFO not full
        if tb.dut.full.value == 0:
            success = await tb.write_data(data)
            if success:
                cocotb.log.debug(f"Writer wrote data: {data}")
            else:
                cocotb.log.debug(f"Writer attempted write but FIFO was full: {data}")
        else:
            cocotb.log.debug("Writer: FIFO full, skipping write")
            
        # Occasionally log status
        if i % 20 == 0:
            status = tb.monitor.get_status()
            cocotb.log.info(f"Writer progress: {i}/{num_transactions}, Queue size: {status['count']}")
    
    cocotb.log.info("Writer coroutine completed")

async def reader_coroutine(tb, num_transactions=100, max_delay=15):
    """Parallel reader coroutine that reads data from FIFO"""
    cocotb.log.info("Reader coroutine started")
    
    transactions_read = 0
    
    while transactions_read < num_transactions:
        # Random delay between read attempts
        delay = random.randint(1, max_delay)
        await ClockCycles(tb.clock, delay)
        
        # Read data if FIFO not empty
        if tb.dut.dout_val.value == 1:
            data = await tb.read_data()
            if data is not None:
                transactions_read += 1
                cocotb.log.debug(f"Reader read data: {data}")
        else:
            cocotb.log.debug("Reader: FIFO empty, waiting...")
            # Wait for data to be available
            await tb.monitor.data_ready_event.wait()
            
        # Occasionally log status
        if transactions_read % 20 == 0:
            status = tb.monitor.get_status()
            cocotb.log.info(f"Reader progress: {transactions_read}/{num_transactions}, Queue size: {status['count']}")
    
    cocotb.log.info("Reader coroutine completed")

async def status_monitor_coroutine(tb, interval=50, timeout=5000):
    """Coroutine that periodically monitors and verifies FIFO status"""
    cocotb.log.info("Status monitor coroutine started")
    
    cycle_count = 0
    while True:
        if cycle_count == timeout:
            print("Exiting Test")
            break
        await ClockCycles(tb.clock, interval)
        cycle_count += interval
        
        status = tb.monitor.get_status()
        
        # Verify FIFO status flags match expected state
        expected_empty = status['empty']
        expected_full = status['full']
        
        actual_empty = ~tb.dut.dout_val.value
        actual_full = tb.dut.full.value
        
        if actual_empty != expected_empty:
            cocotb.log.error(f"Empty flag mismatch at cycle {cycle_count}: Expected {expected_empty}, Got {actual_empty}")
            
        if actual_full != expected_full:
            cocotb.log.error(f"Full flag mismatch at cycle {cycle_count}: Expected {expected_full}, Got {actual_full}")
            
        cocotb.log.info(f"Cycle {cycle_count}: Queue size={status['count']}, "
                       f"Writes={status['write_count']}, Reads={status['read_count']}, "
                       f"Verified={status['data_verified']}, Errors={status['errors']}")

@cocotb.test()
async def test_fifo(dut):
    """Test FIFO with parallel reader and writer coroutines"""
    
    # Create clock
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    # Create central monitor
    monitor = FIFOMonitor(depth=16)
    
    # Initialize testbench
    tb = FIFOTestbench(dut, monitor)
    
    # Reset DUT
    await tb.reset_dut()
    
    cocotb.log.info("Starting parallel FIFO test...")
    
    # Start all coroutines in parallel
    writer_task = cocotb.start_soon(writer_coroutine(tb, num_transactions=200, max_delay=2))
    reader_task = cocotb.start_soon(reader_coroutine(tb, num_transactions=200, max_delay=2))
    monitor_task = cocotb.start_soon(status_monitor_coroutine(tb, interval=100, timeout=5000))
    
    # Wait for both reader and writer to complete
    await Join(writer_task)
    await Join(reader_task)

    print("read and write done")
    
    # Stop the monitor task
    monitor_task.cancel()
    
    # Final verification
    final_status = monitor.get_status()
    cocotb.log.info(f"Final status: {final_status}")
    
    # Verify all data was processed correctly
    assert final_status['errors'] == 0, f"Test failed with {final_status['errors']} errors"
    assert final_status['count'] == 0, f"Expected empty queue, but has {final_status['count']} items"
    assert final_status['write_count'] == final_status['read_count'], "Write/read count mismatch"
    
    cocotb.log.info("Parallel FIFO test completed successfully!")

'''    
@cocotb.test()
async def test_fifo_burst(dut):
    """Test FIFO with burst read/write patterns"""
    
    clock = Clock(dut.clk, 10, unit="ns")
    cocotb.start_soon(clock.start())
    
    monitor = FIFOMonitor(depth=16)
    tb = FIFOTestbench(dut, monitor)
    
    await tb.reset_dut()
    
    # Burst write then burst read
    cocotb.log.info("Testing burst write followed by burst read")
    
    # Write burst
    for i in range(10):
        await tb.write_data(i + 100)
    
    # Read burst
    for i in range(10):
        data = await tb.read_data()
        assert data == i + 100, f"Burst data mismatch: expected {i + 100}, got {data}"
    
    # Test mixed bursts
    cocotb.log.info("Testing mixed read/write bursts")
    
    # Start parallel tasks for mixed operation
    mixed_writer = cocotb.start_soon(writer_coroutine(tb, num_transactions=50, max_delay=3))
    mixed_reader = cocotb.start_soon(reader_coroutine(tb, num_transactions=50, max_delay=5))
    mixed_monitor = cocotb.start_soon(status_monitor_coroutine(tb, interval=50, timeout=5000))
    
    await Join(mixed_writer)
    await Join(mixed_reader)
    mixed_monitor.kill()
    
    # Final check
    final_status = monitor.get_status()
    assert final_status['errors'] == 0, "Burst test had errors"
    assert final_status['count'] == 0, "Queue should be empty after burst test"
    
    cocotb.log.info("Burst operations test completed successfully!")
'''

def test_simple_fifo_runner():
    sim = os.getenv("SIM", "verilator")

    proj_path = Path(__file__).resolve().parent

    sources = [proj_path / "../../rtl/lib/fifo.sv"]

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="fifo",
        always=True,
    )

    runner.test(hdl_toplevel="fifo", test_module="test_fifo,")


if __name__ == "__main__":
    test_simple_fifo_runner()
