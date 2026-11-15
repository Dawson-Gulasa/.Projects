# File: app.py
# Author(s): CSEE 4290 Fall 2021
#
####################
## Changes Fall25 ##
####################
#
# Support for 16 registers by extending register field to 4 bits
# Support to use XZR register as a shortcut for the value zero OR shortcut for R14
# CMP now "stores" to R14 (XZR) and SUBS can be used to store to a destination register
# New instructions MOVF and SAVF added
# Immediate values can now be negative (#0x-1) - This now also works for MOV32
# Labels can be used as immediate values for MOV instructions

import re
import json
import sys
import copy

condition_lookup = {
    "eq": 0,
    "ne": 1,
    "cs": 2,
    "hs": 2,
    "cc": 3,
    "lo": 3,
    "mi": 4,
    "pl": 5,
    "vs": 6,
    "vc": 7,
    "hi": 8,
    "ls": 9,
    "ge": 10,
    "lt": 11,
    "gt": 12,
    "le": 13,
    "al": 14,
    "nv": 15
}


def parse_comments(lines, line_data):
    '''
    remove comment from line

    return line and comment
    '''

    comment = None

    for i, line_dict in enumerate(line_data):

        index = lines[i].find(';')

        if index >= 0:
            lines[i] = lines[i][:index]
            comment = lines[i][index+1:]
            if len(comment) == 0:
                comment = None

        line_data[i]['comment'] = comment
    return lines, line_data
    
def del_blanklines(lines, line_data):
    '''
    remove line if the only data is whitespace
    remove corresponding dicts from line_data
    '''
    cleaned_lines = []
    cleaned_data = []

    re_blank = re.compile(r'^\s*$')
    for i, line in enumerate(lines):
        
        blank_obj = re_blank.match(line)
        if not blank_obj:
            cleaned_lines.append(line)
            cleaned_data.append(line_data[i])

    return cleaned_lines, cleaned_data

def get_line_type(line, type_label, type_instruction, error):
    '''
    input line as a string, return true or false for label, instruction or error
    '''

    re_label = re.compile(r'^([a-zA-Z0-9_]+):\s*$')
    re_instruction = re.compile(r'^\s+\w+')

    label_obj = re_label.match(line)
    instruction_obj = re_instruction.match(line)

    if label_obj and not instruction_obj:
        type_label = True

    elif instruction_obj and not label_obj:
        type_instruction = True
        
    else:
        error = "Could not determine if line is instruction or label"

    return type_label, type_instruction, error

def parse_label(line):
    re_label = r'^([a-zA-Z0-9_]+):\s*$'
    label_obj = re.search(re_label, line)
    
    label = label_obj.group(1) #group 0 contains the entire string, group 1 contains the match

    return label
    
def parse_instruction(line):

    re_mnem = re.compile(r'\s+([A-Za-z.0-9]+).*$')
    re_cond = re.compile(r'[bB]\.([a-zA-Z]+)')
    
    mnemonic_obj = re_mnem.search(line)

    cond = None
    mnem_end_index = None
    mnemonic = None
    error = None
    target = None
    args = []

    if mnemonic_obj:
        mnem_end_index = mnemonic_obj.end(1)
        mnemonic = mnemonic_obj.group(1)

        #save condtion if b.cond in cond variable, rename mnemonic to b.cond
        if 'B.' in mnemonic or 'b.' in mnemonic:
            cond = re_cond.findall(mnemonic)[0]
            mnemonic = 'b.cond'


        #remove mnemonic from line within the function scope for easier parsing
        line = line[mnem_end_index:]
        
        args = parse_arguments(line, cond)
        
    else:
        error = "could not parse mnemonic"
        return mnemonic, args, error

    return mnemonic, args, error

def parse_arguments(line, cond):
    '''
    return a list of singleton dictionaries with argument type as label
    types: register, immediate, shift, condition
    '''

    line = line.replace('\t', '').replace(' ', '')

    if not line:
        return None

    args = line.split(',')

    if cond:
        temp = {'Flg': None}
        temp['Flg'] = cond

        args.insert(0,temp)

    if len(args) == 0:
        return []


    conditions = ['eq', 'ne', 'cs', 'hs', 'cc', 'lo', 'mi', 'pl', 'vs', 'vc', 'hi', 'ls', 'ge', 'lt', 'gt', 'le', 'al', 'nv']

    #convert hex string to int
    for i,arg in enumerate(args):

        if '#0x' in arg:
            temp = {'Imm': None}
            temp['Imm']= int(arg[3:],16)
            args[i] = temp
            continue

        '''
        # This XZR implementation substitues XZR with a 0 immediate value
        if type(arg) == str: #checking if zxr is used for zero register
            if arg.lower() == 'xzr':
                temp = {'Imm': None}
                temp['Imm'] = 0
                args[i] = temp
                continue
        '''

        # This XZR implementation substitues XZR with register 14
        if type(arg) == str: #checking if zxr is used for zero register
            if arg.lower() == 'xzr':
                temp = {'Reg': None}
                temp['Reg'] = 14
                args[i] = temp
                continue
                
        if type(arg) == str: #check type now that some elements have changed
            if 'r' == arg[0] or 'R' == arg[0]:
                temp = {'Reg': None}
                temp['Reg'] = int(arg[1:])
                args[i] = temp
                continue

        if type(arg) == str:
            if '#' in arg: #since already checked hex, # must mean shift value
                temp = {'Imm': None}
                temp['Imm'] = int(arg[1:])
                args[i] = temp
                continue

        if type(arg) == str:
            if arg.lower() in conditions:
                temp = {'Flg': None}
                temp['Flg'] = arg.lower()
                args[i] = temp
                continue

        if type(arg) == str: #assume the last possible argument would be branch target
            temp = {'Imm': None}
            temp['Imm'] = arg
            args[i] = temp
            continue

    return args

def insert_labels_to_instructions(line_data):
    '''
    for dictionaries with labels, insert the label into the label field of the following instruction and remove that entry from the line_data list

    this allows the instruction number to be inferred from the location in the instruction list
    '''
    for i,line_dict in enumerate(line_data):
        label = line_dict['label']
        if label:
            line_data[i+1]['label'] = label
            del line_data[i]
        else:
            continue

    return line_data

def parse_line(i, line, line_dict):

        type_label = False
        type_instruction = False
        error = None
        line_dict['opcode'] = None

        
        type_label, type_instruction, error = get_line_type(line, type_label, type_instruction, error)
        if error:
            line_dict["error"] = error
            return line_dict

        if type_label:

            label = parse_label(line)
            if error:
                line_dict["error"] = error
                return line_dict

            line_dict["label"] = label

            return line_dict

        elif type_instruction:

            mnemonic, args, error = parse_instruction(line)
            if error:
                line_dict["error"] = error
                return line_dict

            line_dict["mnemonic"] = mnemonic
            line_dict["args"] = args

            return line_dict
        else:
            print("typing error") #handle this the correct way
            return line_dict

directives = ['org', 'mov32', 'rmb', 'fcb', 'cmp']

def check_mnemonics(line_data):
    '''
    checks if the given mnemonics are in the list of recognized ISA mnemonics. 
    Also warns the user if halt is not the last mnemonic
    '''
    with open(json_directory) as f:
       instrs = json.load(f)

    mnemonics = []

    for i in instrs.keys():
        opcode = instrs[i]["op_code"]
        mnemonics.append(opcode)

    mnemonics.extend(directives)
    
    for i, line in enumerate(line_data):
        # print(line)
        if not line["mnemonic"] == None:
            parsed_mnemonic = line["mnemonic"].lower()
            if parsed_mnemonic:
                if parsed_mnemonic not in mnemonics:
                    line_data[i]["errors"] = "mnemonic not recognized"
                # MUL, MULS, DIV and DIVS write their second result (high word or
                # remainder) to R12, so R12 should not also be their destination.
                # The spec leaves this to the programmer (F2026.3), so only warn.
                elif parsed_mnemonic in ("mul", "muls", "div", "divs"):
                    args = line["args"] or []
                    if args and args[0].get("Reg") == 12:
                        print("Warning on line", line["line number"], ": R12 should not be the destination of",
                              parsed_mnemonic.upper(), "(R12 receives its high word or remainder)")

    #check if last instruction is halt
    if len(line_data) != 0:
        if not line_data[-1]["mnemonic"] == None:
            last_mnem = line_data[-1]["mnemonic"].lower()
            if last_mnem != 'halt':
                print("Warning: Last instruction is not HALT")

    return line_data



def print_load_asm_error(line_data):
    is_error = False
    for line_dict in line_data:
        if line_dict['errors']:
            print('Syntax error on line', line_dict['line number'])
            is_error = True
        else:
            continue
    
    if is_error:
        quit()


def load_asm(filename):
    line_data = []
    keys = ["label", "mnemonic", "args", "addr", "comment", "line number", "errors", "opcode"]
    try:
        with open(filename) as file:
            lines = file.read().splitlines()
    except:
        print(f"Could not find or could not open '{filename}'")
        quit()

    #initialize line_data and populate line number
    for i, line in enumerate(lines):
        d = dict.fromkeys(keys)
        d["line number"] = i + 1
        line_data.append(d)

    try:
        lines, line_data = parse_comments(lines, line_data)
    except:
        print('error parssing comment')
        quit()


    lines, line_data = del_blanklines(lines, line_data)


    #now parse line by line
    for i, line in enumerate(lines):


        try:
            line_data[i] = parse_line(i, line, line_data[i])
        except:
            line_data[i]['errors'] = "syntax error"

    #turn None types into empty lists for 'args'
    for line in line_data:
        if not line['args']:
            line['args'] = []

    
    
    line_data = insert_labels_to_instructions(line_data)

    
    try:
        line_data = check_mnemonics(line_data)
    except:
        print("Failed checking mnemonics")
        quit()


    print_load_asm_error(line_data)

    return line_data

addr = 0
subindex = 1
def pseudo_mnemonics(index, lines):
    global addr
    global subindex
    if lines[index]["mnemonic"] == "ORG":
        addr = lines[index]["args"][0]["Imm"]
        return True
    elif lines[index]["mnemonic"] == "FCB":
        lines[index]["opcode"] = lines[index]["args"][0]["Imm"]
        return False 
    elif lines[index]["mnemonic"] == "RMB":
        lines[index]["opcode"] = 0
        return False 
    elif lines[index]["mnemonic"] == "MOV32":
        if lines[index]["args"][1]["Imm"] < 0:
            lines[index]["args"][1]["Imm"] = 0xFFFFFFFF + lines[index]["args"][1]["Imm"] + 1
        lines.insert(index + 1, copy.deepcopy(lines[index]))
        lines[index]["mnemonic"] = "MOV"
        lines[index]["args"][1]["Imm"] &= 0xFFFF
        lines[index+1]["mnemonic"] = "MOVT"
        lines[index+1]["args"][1]["Imm"] >>= 16
    elif lines[index]["mnemonic"] == "CMP" or lines[index]["mnemonic"] == "cmp":
        lines[index]["mnemonic"] = "subs"
        lines[index]["args"].append(lines[index]["args"][1])
        lines[index]["args"][1] = lines[index]["args"][0]
        lines[index]["args"][0] = {"Reg": 14}
    return False


labels = {}
def assemble_from_token(lines):
    global addr
    global labels
    f = open(json_directory)
    instrs = json.load(f)
    for i, line in enumerate(lines):
        if line["label"] is not None:
            labels[line["label"]] = addr
        if(pseudo_mnemonics(i, lines)):
            pass
        else:
            lines[i]["addr"] = addr
            addr += 4

def get_arg_keys(arg_list):
    keys = []
    try:
        for arg in arg_list:
            keys.append(list(arg.keys())[0])
        return keys
    except TypeError:
        return [] 
        
def assemble_opcode(dict):
    instrs = None
    opcodes = []
    with open(json_directory) as f:
       instrs = json.load(f)    
    for (lineNum, line) in enumerate(dict):

        opcode = 0
        opcode_len = 0
        label = None
        assembled = False

        if line["mnemonic"] is None:
            print("Missing mnemonic for line {}. Skipping instruction. Error: {}".format(line["line number"], line["error"]))
            continue

        for inst in instrs:
            # Matches the op_code mnemonic and the number of args

            argsMatch = get_arg_keys(instrs[inst]["args"]) == get_arg_keys(line["args"])
            opCodeMatch = instrs[inst]["op_code"].casefold() == line["mnemonic"].casefold()

            if not line["opcode"] and opCodeMatch and argsMatch:
                assembled = True
                # ors the op_code as the first 7 bits
                try:
                    opcode = opcode | int(instrs[inst]["instr"], 2)
                    opcode_len = opcode_len + 7
                except KeyError:
                    print("Mnemonic " + line["mnemonic"] + " not found. Line: ",line["line number"])
                    continue
                except:
                    print("I don't know how but you broke it. Line: ",line["line number"])
                    continue
                # Gets the arguments
                for (index, arg) in enumerate(line["args"]):
                    if (arg.get("Reg") or (arg.get("Reg") == 0)):
                        # Shifts the current op_code right 4 and adds the register
                        opcode = (opcode << 4)                  # changed from 3 to 4
                        opcode_len = opcode_len + 4        # changed from 3 to 4
                        try:
                            opcode = opcode | int(arg["Reg"])
                        except TypeError:
                            print(arg["Reg"] + "is not a number. Line: ", line["line number"])
                            continue
                        except:
                            print("I don't know how but you broke it. Line: ",line["line number"])
                            continue
                        # Encodes the flags
                    elif arg.get("Flg"):
                        # Shifts the op_code right 4 and adds the flag
                        try:
                            opcode = (opcode << 4 | condition_lookup[arg["Flg"].lower()])
                        except KeyError:
                            print("Could not find " + arg["Flg"] + "flag. Line: ",line["line number"])
                            continue
                        except:
                            print("I don't know how but you broke it. Line: ",line["line number"])
                            continue
                        opcode_len = opcode_len + 4
                        # Encodes the Immediate value
                    elif arg.get("Imm"):
                        # make sure immediate is 2's compliment if negative (16 bit here)
                        # Shifts the op_code to make the immediate bits 15-0
                        offset = 32 - opcode_len
                        opcode = (opcode << offset)
                        opcode_len = opcode_len + offset
                        if type(arg["Imm"]) == str:
                            try:
                                temp = labels[arg["Imm"]] - line["addr"]
                                # Uses absolute address for mov instruction (for loading addresses into registers)
                                if line["mnemonic"].lower() == "mov":
                                    temp = labels[arg["Imm"]]
                                # Converts to 2's complement if negative
                                if temp < 0:
                                    temp = int(hex(((abs(temp) ^ 0xffff) + 1) & 0xffff),16)
                                opcode = opcode | temp
                            except KeyError:
                                print("Label " + arg["Imm"] + " is not defined. Line: ", line["line number"])
                                continue
                            except:
                                print("I don't know how but you broke it. Line: ",line["line number"])
                                continue
                        else:
                            if arg["Imm"] < 0:
                                arg["Imm"] = 0xFFFF + arg["Imm"] + 1
                            opcode = opcode | arg["Imm"]
                            # print("Something wrong with Imm")
                # Ensures to opcode is 32 bits if it does not have leading zeros
                if len(bin(opcode)[2:]) < 32:
                    opcode = opcode << (32 - opcode_len)
                opcodes.append((opcode, line["addr"], line))
        if(line["opcode"] or line["mnemonic"].lower() == "fcb"):
            # Jake: this IF statement failed with FCB #0x0 since the full opcode is 0 and that is a valid opcode
            opcodes.append((line["opcode"], line["addr"], line))
        if not assembled and line["opcode"] == None and not line["mnemonic"] == "ORG":
            print("Instruction {instruction} on line {line} not found. Possible incorrect number of arguments.".format(instruction = line["mnemonic"],line=line["line number"]))
    write_file(opcodes)
    return opcodes

def write_file(opcodes):
    with open("output.mem","w") as file:
        last_addr = 0
        for opcode, addr, _ in opcodes:
            if addr != last_addr + 4:
                file.write("@" + '{0:08X}'.format(addr) + "\n")
            hex_string = '{0:08X} \n'.format(opcode)
            file.write(" ". join(hex_string[i:i+2] for i in range(0, len(hex_string),2)))
            last_addr = addr
    with open("output.lst","w") as file:
        for opcode, addr, inst in opcodes:
            hex_string = '{0:08X}'.format(opcode)
            hex_address = '{0:08X}'.format(inst["addr"])
            file.write(hex_address + " | " + hex_string + ": \t" + (inst["label"] +
                ": \t" if inst["label"] is not None else "\t\t")+
                inst["mnemonic"] + "\t\n")



if __name__ == '__main__':
    dict = {}
    if(len(sys.argv) == 3):
        global json_directory 
        json_directory = sys.argv[2]
        dict = load_asm(sys.argv[1])
    else:
        print("2 arguments must be given")
    assemble_from_token(dict)
    opcodes = assemble_opcode(dict)