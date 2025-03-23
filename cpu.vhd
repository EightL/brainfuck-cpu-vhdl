-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2024 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): jmeno <xsevcim00 AT stud.fit.vutbr.cz>
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
port (
CLK   : in std_logic;  -- hodinovy signal
RESET : in std_logic;  -- asynchronni reset procesoru
EN    : in std_logic;  -- povoleni cinnosti procesoru

-- synchronni pamet RAM
DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
DATA_RDWR  : out std_logic;                    -- cteni (1) / zapis (0)
DATA_EN    : out std_logic;                    -- povoleni cinnosti

-- vstupni port
IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
IN_VLD    : in std_logic;                      -- data platna
IN_REQ    : out std_logic;                     -- pozadavek na vstup data

-- vystupni port
OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
OUT_INV  : out std_logic;                      -- pozadavek na aktivaci inverzniho zobrazeni (1)
OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

-- stavove signaly
READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
);
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

---------------------- Signals --------------------------

-- CNT register
signal cnt_reg : std_logic_vector(7 downto 0);
signal cnt_inc : std_logic;
signal cnt_dec : std_logic;
signal cnt_reset : std_logic;

-- PC register
signal pc_reg  : std_logic_vector(12 downto 0);
signal pc_inc  : std_logic;
signal pc_dec  : std_logic;
signal pc_load : std_logic;
signal pc_load_value : std_logic_vector(12 downto 0);

-- PTR register
signal ptr_reg : std_logic_vector(12 downto 0);
signal ptr_inc : std_logic;
signal ptr_dec : std_logic;
signal ptr_load : std_logic;
signal ptr_load_value : std_logic_vector(12 downto 0);

-- TMP register
signal tmp_reg : std_logic_vector(7 downto 0);
signal tmp_load : std_logic;
signal tmp_load_value : std_logic_vector(7 downto 0);

-- Multiplexors
signal mx1_sel : std_logic;
signal mx2_sel : std_logic_vector(1 downto 0);

-- Helper READY_reg, DONE_reg signals
signal READY_reg : std_logic := '0';
signal DONE_reg  : std_logic := '0';

----------------------- States ---------------------------
type FSM_STATE is (
fsm_start,
fsm_find_at,
fsm_find_at_read,
fsm_fetch,
fsm_fetch_read,
fsm_decode,

fsm_ptr_inc,
fsm_ptr_dec,

fsm_val_inc_start,
fsm_val_inc_read,
fsm_val_inc_do,

fsm_val_dec_start,
fsm_val_dec_read,
fsm_val_dec_do,

fsm_while_begin,
fsm_while_begin_do,
fsm_while_begin_check,
fsm_while_begin_cycle,
fsm_while_begin_cycle_check,
fsm_while_begin_cycle_read,
fsm_while_begin_cycle_update,

fsm_while_end_do,
fsm_while_end_check,
fsm_while_end_cycle,
fsm_while_end_cycle_check,
fsm_while_end_cycle_read,
fsm_while_end_cycle_update,

fsm_store_tmp,
fsm_store_tmp_read,

fsm_load_tmp_start,

fsm_write_req,
fsm_write_read,

fsm_read_req,
fsm_read,

fsm_other,
fsm_halt

);
signal current_state : FSM_STATE := fsm_start;
signal next_state : FSM_STATE;


begin
    -- I chose to handle READY and DONE signals are managed separately with READY_reg and DONE_reg
    READY <= READY_reg;
    DONE  <= DONE_reg;
    OUT_INV <= '0';

    ----------------------  PC ----------------------- 
    pc: process (CLK, RESET)
    begin
        if RESET = '1' then 
            pc_reg <= (others => '0');
        elsif rising_edge(CLK) then 
            if pc_load = '1' then
                pc_reg <= pc_load_value;
            elsif pc_inc = '1' then 
                pc_reg <= pc_reg + 1;
            elsif pc_dec = '1' then 
                pc_reg <= pc_reg - 1;
            end if;
        end if; 
    end process;


    ----------------------  PTR -----------------------
    ptr: process (CLK, RESET)
    begin
        if RESET = '1' then
            ptr_reg <= (others => '0');
        elsif rising_edge(CLK) then
            if ptr_load = '1' then
                ptr_reg <= ptr_load_value;
            elsif ptr_inc = '1' then
                ptr_reg <= ptr_reg + 1;
            elsif ptr_dec = '1' then
                ptr_reg <= ptr_reg - 1;
            end if;
        end if;
    end process;


    ----------------------  CNT -----------------------
    cnt: process (CLK, RESET)
    begin
        if RESET = '1' then
            cnt_reg <= (others => '0');
        elsif rising_edge(CLK) then
            if cnt_reset = '1' then
                cnt_reg <= (others => '0');
            elsif cnt_inc = '1' then
                cnt_reg <= cnt_reg + 1;
            elsif cnt_dec = '1' then
                cnt_reg <= cnt_reg - 1;
            end if;
        end if;
    end process;

    ----------------------  TMP -----------------------
    tmp: process(CLK, RESET)
    begin
        if RESET = '1' then
            tmp_reg <= (others => '0');
        elsif rising_edge(CLK) then
            if tmp_load = '1' then
                tmp_reg <= tmp_load_value;
            end if;
        end if;
    end process;


    ------------------  Multiplexor 1 -----------------
    mx1: process (mx1_sel, pc_reg, ptr_reg) is
    begin
    case mx1_sel is 
        when '0' => DATA_ADDR <= pc_reg;
        when '1' => DATA_ADDR <= ptr_reg;
        when others => DATA_ADDR <= (others => '0');
    end case;
    end process;


    ------------------  Multiplexor 2 -----------------
    mx2: process (mx2_sel, IN_DATA, DATA_RDATA, tmp_reg) is
    begin
    case mx2_sel is
        when "00" => DATA_WDATA <= IN_DATA;
        when "01" => DATA_WDATA <= (DATA_RDATA + 1);
        when "10" => DATA_WDATA <= (DATA_RDATA - 1);
        when "11" => DATA_WDATA <= tmp_reg;
        when others => DATA_WDATA <= (others => '0');
    end  case;
    end process;  


    -------------  Current State Logic -----------------
    current_state_logic: process (CLK, RESET) is 
    begin
    if RESET = '1' then
        current_state <= fsm_start;
    elsif rising_edge(CLK) then 
        current_state <= next_state;
    end if;
    end process;

    -- ----------------------------------------------------------------------------
    --                                  FSM
    -- ----------------------------------------------------------------------------
    fsm: process (EN, DATA_RDATA, IN_VLD, OUT_BUSY, current_state) is
    begin 
    --------- Control signal initialization ----------
    pc_inc <= '0';
    pc_dec <= '0';
    pc_load <= '0';
    pc_load_value <= (others => '0');

    ptr_inc <= '0';
    ptr_dec <= '0';
    ptr_load <= '0';
    ptr_load_value <= (others => '0');

    cnt_inc <= '0';
    cnt_dec <= '0';
    cnt_reset <= '0';

    tmp_load <= '0';
    tmp_load_value <= (others => '0');

    mx1_sel <= '0';
    mx2_sel <= "00";

    IN_REQ <= '0';
    OUT_WE <= '0';
    DATA_EN <= '0';
    DATA_RDWR <= '1';  -- default to read

    ------------------- FSM Logic ---------------------
    if EN = '1' then
        --------- Start and find '@' -------
        case current_state is
            --Start, Find '@'
            when fsm_start => 
                -- READY and DONE signals are managed separately with READY_reg and DONE_reg
                next_state <= fsm_find_at;

            when fsm_find_at =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mx1_sel <= '0'; 
                next_state <= fsm_find_at_read;

            when fsm_find_at_read =>
                if DATA_RDATA /= X"40" then  -- not '@'
                    pc_inc <= '1';
                    next_state <= fsm_find_at;
                else  -- found '@'
                    ptr_load <= '1';
                    ptr_load_value <= pc_reg + 1;
                    pc_load <= '1';
                    pc_load_value <= (others => '0');
                    next_state <= fsm_fetch;
                end if;

            -------------- Fetch ---------------
            when fsm_fetch => 
                DATA_EN <= '1';
                DATA_RDWR <= '1';  -- read
                mx1_sel <= '0';    -- select PC for memory address
                next_state <= fsm_fetch_read;

            when fsm_fetch_read =>
                next_state <= fsm_decode;

            -------------- Decode --------------
            when fsm_decode => 
                case DATA_RDATA is
                    when X"3E" => next_state <= fsm_ptr_inc;        -- >
                    when X"3C" => next_state <= fsm_ptr_dec;        -- <
                    when X"2B" => next_state <= fsm_val_inc_start;  -- +
                    when X"2D" => next_state <= fsm_val_dec_start;  -- -
                    when X"5B" => next_state <= fsm_while_begin;    -- [
                    when X"5D" => next_state <= fsm_while_end_do;   -- ]
                    when X"24" => next_state <= fsm_store_tmp;      -- $
                    when X"21" => next_state <= fsm_load_tmp_start; -- !
                    when X"2E" => next_state <= fsm_write_req;      -- .
                    when X"2C" => next_state <= fsm_read_req;       -- ,
                    when X"40" => next_state <= fsm_halt;           -- @
                    when others => next_state <= fsm_other;         -- other
                end case;

            ----------- OPERATIONS -------------
            -------------- '>' -----------------
            when fsm_ptr_inc =>
                ptr_inc <= '1';
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -------------- '<' -----------------
            when fsm_ptr_dec =>
                ptr_dec <= '1';
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -------------- '+' -----------------
            when fsm_val_inc_start =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mx1_sel <= '1';
                next_state <= fsm_val_inc_read;

            when fsm_val_inc_read =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx1_sel <= '1';
                mx2_sel <= "01"; 
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -------------- '-' -----------------
            when fsm_val_dec_start =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mx1_sel <= '1';
                next_state <= fsm_val_dec_read;

            when fsm_val_dec_read =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx1_sel <= '1';
                mx2_sel <= "10"; 
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -------------- '[' -----------------
            when fsm_while_begin =>
                pc_inc <= '1';
                next_state <= fsm_while_begin_do;
            
            when fsm_while_begin_do =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mx1_sel <= '1';
                next_state <= fsm_while_begin_check;
            
            when fsm_while_begin_check =>
                if DATA_RDATA /= X"00" then
                    next_state <= fsm_fetch;
                else
                    cnt_reset <= '1';
                    next_state <= fsm_while_begin_cycle;
                end if;
            
            when fsm_while_begin_cycle =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mx1_sel <= '0';
                next_state <= fsm_while_begin_cycle_read;
            
            when fsm_while_begin_cycle_read =>
                pc_inc <= '1';
                if DATA_RDATA = X"5B" then  -- '['
                    cnt_inc <= '1';
                elsif DATA_RDATA = X"5D" then  -- ']'
                    cnt_dec <= '1';
                end if;
                next_state <= fsm_while_begin_cycle_update;
            
            when fsm_while_begin_cycle_update =>
                if cnt_reg = X"00" then
                    next_state <= fsm_fetch;
                else
                    next_state <= fsm_while_begin_cycle;
                end if;

            -------------- ']' -----------------
            when fsm_while_end_do =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mx1_sel <= '1';
                next_state <= fsm_while_end_check;

            when fsm_while_end_check =>
                if DATA_RDATA /= X"00" then
                    cnt_reset <= '1';
                    next_state <= fsm_while_end_cycle;
                else
                    pc_inc <= '1';
                    next_state <= fsm_fetch;
                end if;

            when fsm_while_end_cycle =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';
                mx1_sel <= '0';
                next_state <= fsm_while_end_cycle_read;

            when fsm_while_end_cycle_read =>
                pc_dec <= '1';
                if DATA_RDATA = X"5D" then  -- ']'
                    cnt_inc <= '1';
                elsif DATA_RDATA = X"5B" then  -- '['
                    cnt_dec <= '1';
                end if;
                next_state <= fsm_while_end_cycle_update;

            when fsm_while_end_cycle_update =>
                if cnt_reg = X"00" then
                    pc_inc <= '1';
                    next_state <= fsm_fetch;
                else
                    next_state <= fsm_while_end_cycle;
                end if;

            -------------- '$' -----------------
            when fsm_store_tmp =>
                DATA_EN <= '1';
                DATA_RDWR <= '1';  -- read
                mx1_sel <= '1';    -- select ptr
                next_state <= fsm_store_tmp_read;

            when fsm_store_tmp_read =>
                tmp_load <= '1';
                tmp_load_value <= DATA_RDATA;
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -------------- '!' -----------------
            when fsm_load_tmp_start =>
                DATA_EN <= '1';
                DATA_RDWR <= '0';
                mx1_sel <= '1';
                mx2_sel <= "11"; -- tmp_reg
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -------------- '.' -----------------
            when fsm_write_req => 
                if OUT_BUSY = '1' then 
                    next_state <= fsm_write_req;
                else
                    DATA_EN <= '1';
                    DATA_RDWR <= '1';  -- read
                    mx1_sel <= '1';
                    next_state <= fsm_write_read;
                end if;

            when fsm_write_read =>
                OUT_WE <= '1';
                OUT_DATA <= DATA_RDATA;
                pc_inc <= '1';
                next_state <= fsm_fetch;

            -------------- ',' -----------------
            when fsm_read_req =>
                IN_REQ <= '1';
                if IN_VLD = '1' then
                    next_state <= fsm_read;
                else
                    next_state <= fsm_read_req;
                end if;

            when fsm_read =>
                DATA_EN <= '1';
                DATA_RDWR <= '0'; 
                mx1_sel <= '1';
                mx2_sel <= "00";
                pc_inc <= '1';
                next_state <= fsm_fetch;

            ----------- other (comments) ---------
            when fsm_other =>
                pc_inc <= '1';
                next_state <= fsm_fetch;

            when fsm_halt =>
                next_state <= fsm_halt; -- Remain in halt state

            when others =>
                next_state <= fsm_start; -- Reset to start state
        end case;
    else
        -- when EN = '0', hold the current state
        next_state <= current_state;
    end if;
    end process;

    -- Helping process to update READY_reg and DONE_reg
    process (CLK, RESET)
    begin
        if RESET = '1' then
            READY_reg <= '0';
            DONE_reg  <= '0';
        elsif rising_edge(CLK) then
            READY_reg <= READY_reg;
            DONE_reg <= DONE_reg;
            if EN = '1' then
                -- When '@' is found set READY
                if current_state = fsm_find_at_read and DATA_RDATA = X"40" then
                    READY_reg <= '1';
                end if;
                -- When FSM finishes set DONE
                if current_state = fsm_halt then
                    DONE_reg <= '1';
                end if;
            end if;
        end if;
    end process;

end behavioral;