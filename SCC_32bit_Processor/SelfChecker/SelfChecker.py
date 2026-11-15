import argparse
import csv

# Compares two files and stores the differences in a list
# Compares each individual bytes and stores the output in Binary
# open files: sourceCSV = output to test | verificationCSV = correct output (from emulator)
def CompareFiles(sourceFile,verificationFile,args,allFlag=False):

    differences = []
    errorFound = False
    instructionStatus = ''
    dataStatus = ''

    # prints out differences for individual bytes
    if (args.byte is True):
        for sourceLine, verificationLine in zip(sourceFile,verificationFile):
            if (sourceLine[1] != 'Value'): # skips column labels in CSV
                # checks for errors in instruction memory by checking if an error
                # is found up to the start of data memory
                # 0x0400 -> start of data memory
                if (sourceLine[0] == '0x00000400'):
                    # outputs color coded using ANSI escape sequences -> PASS = green | Fail = red
                    if (not errorFound):
                        instructionStatus = '\033[92mPASS\033[0m'
                    else:
                        instructionStatus = '\033[91mFAIL\033[0m'
                    errorFound = False

                # splits a 32-bit word into 4 8-bit binary strings
                for i in range(4):
                    # converts 8-bit hex into binary
                    address = hex(int(sourceLine[0][2:10],16) + i)
                    address = '0x' + address[2:].upper().zfill(8)
                    # calculates which byte of the 32-bit word is currently being checked
                    index = (6 - i*2) + 2
                    # converts 8-bit hex into binary
                    sourceHex = sourceLine[1][index:(index+2)]
                    sourceBin = bin(int(sourceHex, 16))[2:].zfill(8)
                    verificationHex = verificationLine[1][index:(index+2)]
                    verificationBin = bin(int(verificationHex, 16))[2:].zfill(8)

                    # If there is a different byte, store the two lines and
                    # the memory location in the differences list
                    if ((sourceBin != verificationBin) or allFlag):
                        if (sourceBin != verificationBin):
                            errorFound = True
                            if (args.condensed):
                                differences.append('[%s] [0b%s | 0b%s] \033[91mFAIL\033[0m'%(address,verificationBin,sourceBin))
                            else:
                                differences.append('[%s] \033[91mFAIL\033[0m\nExpected:0b%s\nReceived:0b%s\n'%(address,verificationBin,sourceBin))
                        else:
                            if (args.condensed):
                                differences.append('[%s] [0b%s | 0b%s] \033[92mPASS\033[0m'%(address,verificationBin,sourceBin))
                            else:
                                differences.append('[%s] \033[92mPASS\033[0m\nExpected:0b%s\nReceived:0b%s\n'%(address,verificationBin,sourceBin))

    # prints out differences a word at a time
    else:
        for sourceLine, verificationLine in zip(sourceFile,verificationFile):
            if (sourceLine[1] != 'Value'):
                # format verilog output to have all uppercase hex
                sourceLine[1] = '0x'+sourceLine[1][2:10].upper()
                # checks for errors in instruction memory by checking if an error
                # is found up to the start of data memory
                # 0xD500 -> start of data memory
                if (sourceLine[0] == '0x00000400'):
                    # outputs color coded using ANSI escape sequences -> PASS = green | Fail = red
                    if (not errorFound):
                        instructionStatus = '\033[92mPASS\033[0m'
                    else:
                        instructionStatus = '\033[91mFAIL\033[0m'
                    errorFound = False

                # If there is a different byte, store the two lines and
                # the memory location in the differences list
                if ((sourceLine[1] != verificationLine[1]) or allFlag):
                    if (sourceLine[1] != verificationLine[1]):
                        errorFound = True
                        if (args.condensed):
                            differences.append('[%s] [%s | %s] \033[91mFAIL\033[0m'%(verificationLine[0],verificationLine[1],sourceLine[1]))
                        else:
                            differences.append('[%s] \033[91mFAIL\033[0m\nExpected:%s\nReceived:%s\n'%(verificationLine[0],verificationLine[1],sourceLine[1]))
                    else:
                        if (args.condensed):
                            differences.append('[%s] [%s | %s] \033[92mPASS\033[0m'%(verificationLine[0],verificationLine[1],sourceLine[1]))
                        else:
                            differences.append('[%s] \033[92mPASS\033[0m\nExpected:%s\nReceived:%s\n'%(verificationLine[0],verificationLine[1],sourceLine[1]))

    # checks for errors in data memory by checking if an error
    # is found from start of data memory to the end of memory
    if (not errorFound):
        dataStatus = '\033[92mPASS\033[0m'
    else:
        dataStatus = '\033[91mFAIL\033[0m'
    
    return differences, instructionStatus, dataStatus



###################
## Program Intro ##
###################

# Setup ArgumentParser object to parse flags
parser = argparse.ArgumentParser(
                    prog='SelfChecker',
                    description='Compares two memory output files and outputs the differences.',
                    epilog='Written by CSEE 4290 Fall 2023')

# Add optional flags to parser object
parser.add_argument('-a','--all',action='store_true',help='outputs the entire contents of memory',required=False)
parser.add_argument('-b','--byte',action='store_true',help='outputs differences at byte (8-bit) locations in memory',required=False)
parser.add_argument('-w','--word',action='store_true',help='outputs differences at word (32-bit) locations in memory (default)',required=False)
parser.add_argument('-c','--condensed',action='store_true',help='outputs differences in a condensed, column, colored format',required=False)
parser.add_argument('-e','--expanded',action='store_true',help='outputs differences in a verbose format (default)',required=False)
parser.add_argument('-f','--file',action='store',help='redirects output to specified text file',required=False)
parser.add_argument('-s','--source',action='store',help='select the memory output from the source computer to test',required=True)
parser.add_argument('-v','--verification',action='store',help='select the memory output from the known correct output for verification',required=True)

args = parser.parse_args()

flagErrors = []
# adds an error if both word and byte flag are used
if (args.word and args.byte):
    flagErrors.append('error: byte and word flags are mutually exclusive')
# adds an error if both condensed and expanded flag are used
if (args.condensed and args.expanded):
    flagErrors.append('error: condensed and expanded flags are mutually exclusive')

# prints usage errors if any found and exits the program
if (flagErrors):
    parser.print_usage()
    for line in flagErrors:
        print(line)
    parser.exit()

# open files: source = output to test | verification = correct output (from emulator)
sourceFile = csv.reader(open(args.source))
verificationFile = csv.reader(open(args.verification))

differences, instructionStatus, dataStatus = CompareFiles(sourceFile,verificationFile,args,args.all)

# Outputs to terminal by default
# Otherwise outputs to file specified by file flag
print('Instruction Memory: %s'%instructionStatus)
print('Data Memory: %s'%dataStatus)
if (differences):
    # prints errors in differences list to standard outupt
    if (args.file is None):
        print('\nMemory Output\n')
        if (args.condensed):
            print(' Address      Expected     Received')
        for error in differences:
            print(error)
    # prints errors in differences list to specified file
    else:
        outputFile = open(args.file, 'w')
        outputFile.write('Memory Output\n\n')
        if (args.condensed):
            outputFile.write(' Address      Expected     Received\n')
        for error in differences:
            outputFile.write('%s\n'%error)
        outputFile.close()