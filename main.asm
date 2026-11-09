TITLE AsmVault Fixed Single-File ATM - COAL Tier 1/2/3 + ShowMsgBoxAsk + Gotoxy Boxes
INCLUDE Irvine32.inc

; =============================================================================
; WIN32 GUARDS
; =============================================================================

IFNDEF SYSTEMTIME
SYSTEMTIME STRUCT
    wYear         WORD ?
    wMonth        WORD ?
    wDayOfWeek    WORD ?
    wDay          WORD ?
    wHour         WORD ?
    wMinute       WORD ?
    wSecond       WORD ?
    wMilliseconds WORD ?
SYSTEMTIME ENDS
ENDIF

IFNDEF GENERIC_WRITE
GENERIC_WRITE EQU 40000000h
ENDIF

IFNDEF GENERIC_READ
GENERIC_READ EQU 80000000h
ENDIF

IFNDEF FILE_SHARE_READ
FILE_SHARE_READ EQU 00000001h
ENDIF

IFNDEF FILE_SHARE_WRITE
FILE_SHARE_WRITE EQU 00000002h
ENDIF

IFNDEF OPEN_ALWAYS
OPEN_ALWAYS EQU 4
ENDIF

IFNDEF OPEN_EXISTING
OPEN_EXISTING EQU 3
ENDIF

IFNDEF FILE_ATTRIBUTE_NORMAL
FILE_ATTRIBUTE_NORMAL EQU 00000080h
ENDIF

IFNDEF FILE_END
FILE_END EQU 2
ENDIF

IFNDEF FILE_BEGIN
FILE_BEGIN EQU 0
ENDIF

IFNDEF INVALID_HANDLE_VALUE
INVALID_HANDLE_VALUE EQU 0FFFFFFFFh
ENDIF

FILE_SHARE_BOTH EQU 00000003h

; =============================================================================
; MESSAGE BOX CONSTANTS
; =============================================================================

IFNDEF MB_YESNO
MB_YESNO EQU 4
ENDIF

IFNDEF MB_ICONQUESTION
MB_ICONQUESTION EQU 32h
ENDIF

IFNDEF IDYES
IDYES EQU 6
ENDIF

IFNDEF IDNO
IDNO EQU 7
ENDIF

MB_CONFIRM_TYPE EQU MB_YESNO + MB_ICONQUESTION

; =============================================================================
; CONSTANTS
; =============================================================================

MAX_ACCOUNTS          = 50
NAME_LEN              = 20
FILE_MAGIC            = 564D5341h       ; 'ASMV'
DAILY_LIMIT           = 25000
MIN_NOTE              = 500
ADMIN_ACC_NO          = 99999999

SESSION_TIMEOUT_MS    = 60000
MAX_DEPOSIT           = 500000
MIN_PIN_LEN           = 4

STMT_MAX              = 5
STMT_LINE_LEN         = 128
STMT_LINES_SIZE       = 640
STMT_BUFFER_SIZE      = 32768

VAULT_ROWS            = 3
VAULT_COLS            = 3
COL_VALUE             = 0
COL_STOCK             = 1
COL_DISP              = 2
DENOM_COUNT           = 3

; Boxed UI layout constants
BOX_LEFT              = 4
BOX_TOP               = 2
BOX_WIDTH             = 62
MENU_HEIGHT           = 17
ADMIN_HEIGHT          = 15

SPLASH_LEFT           = 8
SPLASH_TOP            = 5
SPLASH_WIDTH          = 60
SPLASH_HEIGHT         = 9

CONFIRM_LEFT          = 8
CONFIRM_TOP           = 6
CONFIRM_WIDTH         = 60
CONFIRM_HEIGHT        = 8
MSGBOX_HEIGHT         = 8

; Character constants
CHAR_MINUS            EQU '-'
CHAR_PLUS             EQU '+'
CHAR_PIPE             EQU '|'
CHAR_SPACE            EQU ' '
CHAR_COLON            EQU ':'
CHAR_STAR             EQU '*'
CHAR_CR               EQU 13
CHAR_LF               EQU 10
CHAR_ENTER            EQU 13
CHAR_BACKSPACE        EQU 8

; Status codes
OK                    EQU 0
E_NOT_FOUND           EQU 1
E_BAD_PIN             EQU 2
E_LOCKED              EQU 3
E_INSUFFICIENT        EQU 4
E_DAILY_LIMIT         EQU 5
E_BAD_DENOM           EQU 6
E_INVALID_AMT         EQU 7
E_OVERFLOW            EQU 8
E_FILE                EQU 9
E_SAME_ACCOUNT        EQU 10
E_TIMEOUT             EQU 11
E_VAULT_LOW           EQU 12
E_ADMIN_LOCKED        EQU 13

; Console colors
COLOR_DEFAULT         = lightGray + (black * 16)
COLOR_TITLE           = yellow + (black * 16)
COLOR_SUCCESS         = lightGreen + (black * 16)
COLOR_ERROR           = lightRed + (black * 16)
COLOR_PROMPT          = lightCyan + (black * 16)
COLOR_HEADER          = white + (blue * 16)

; =============================================================================
; MACROS
; =============================================================================

mWrite MACRO msg
    mov edx, OFFSET msg
    call WriteString
ENDM

mNewLine MACRO
    call Crlf
ENDM

mShowError MACRO code
    mov eax, code
    mov edx, errTable[eax*4]
    call WriteString
ENDM

; =============================================================================
; STRUCTURES
; =============================================================================

ACCOUNT STRUCT
    accNo          DWORD  ?
    pinHash        DWORD  ?
    salt           DWORD  ?
    balance        DWORD  ?
    dailyWithdrawn DWORD  ?
    lastWdrDate    DWORD  ?
    holderName     BYTE   NAME_LEN DUP(0)
    failCount      BYTE   0
    status         BYTE   0
    padding        WORD   0
ACCOUNT ENDS

FILE_HEADER STRUCT
    magic          DWORD FILE_MAGIC
    version        DWORD 2
    accountCount   DWORD 0
    checksum       DWORD 0
    txIdCounter    DWORD 10000
    totalTxLow     DWORD 0
    totalTxHigh    DWORD 0
    adminSalt      DWORD 0
    adminPinHash   DWORD 0
FILE_HEADER ENDS

; =============================================================================
; DATA SECTION
; =============================================================================

.data

; File names
fnAccounts BYTE "accounts.dat", 0
fnLog      BYTE "txlog.txt", 0

; Core database
dbHeader        FILE_HEADER <>
accounts        ACCOUNT MAX_ACCOUNTS DUP(<>)
accNoIndex      DWORD MAX_ACCOUNTS DUP(0)
currentAccIdx   DWORD -1

; 2D vault table: value, stock, dispensed
vaultTable DWORD 5000, 100, 0
           DWORD 1000, 300, 0
           DWORD 500,  500, 0

denomPlanned DWORD DENOM_COUNT DUP(0)

; Buffers
rawPinBuffer  BYTE 16 DUP(0)
pinConfirmBuf BYTE 16 DUP(0)
logBuffer     BYTE 512 DUP(0)
inputBuf      BYTE 64 DUP(0)
accFilter     BYTE 12 DUP(0)
stmtBuffer    BYTE STMT_BUFFER_SIZE DUP(0)
stmtLines     BYTE STMT_LINES_SIZE DUP(0)

bytesWritten  DWORD 0
appendPtr     DWORD ?
sysTime       SYSTEMTIME <>

; Runtime state
enteredPinLen  DWORD ?
lastActivity   DWORD ?
stmtCount      DWORD ?
adminFailCount BYTE 0
adminLocked    BYTE 0
menuChoice     BYTE ?
dummySalt      DWORD 0A5A5A5A5h

; Confirmation / message-box data
confirmMsg          BYTE 128 DUP(0)
strConfirmTitle     BYTE "AsmVault Confirmation", 0
strConfirmWdrPrefix BYTE "Confirm withdrawal of PKR ", 0
strConfirmXfrPrefix BYTE "Confirm transfer of PKR ", 0
strConfirmSuffix    BYTE "? (Yes/No)", 0
strCancelled        BYTE "Transaction cancelled by user.", 0
strYNPrompt         BYTE "Enter Y or N: ", 0

; Seed PIN strings
strPin1 BYTE "1234", 0
strPin2 BYTE "5555", 0
strPin3 BYTE "9999", 0

; UI strings
lineBorder       BYTE "==================================================", 0
strSplashTitle   BYTE "WELCOME TO FAST NATIONAL BANK", 0
strSplashSub     BYTE "-- 24/7 ATM SERVICES --", 0
strPressKey      BYTE "Press any key to continue...", 0

strAccPrompt     BYTE "Enter 8-digit Account Number: ", 0
strPinPrompt     BYTE "Enter 4-digit PIN: ", 0
strLoginFailed   BYTE "Error: Invalid Account Number or PIN.", 0
strAccLocked     BYTE "Error: Account LOCKED due to repeated failed attempts.", 0

strMenuHeader    BYTE "MAIN ATM MENU (CUSTOMER)", 0
strMenuOpt1      BYTE "[1] Check Account Balance", 0
strMenuOpt2      BYTE "[2] Cash Withdrawal", 0
strMenuOpt3      BYTE "[3] Cash Deposit", 0
strMenuOpt4      BYTE "[4] Funds Transfer", 0
strMenuOpt5      BYTE "[5] Change PIN", 0
strMenuOpt6      BYTE "[6] Mini Statement", 0
strMenuOpt7      BYTE "[7] Logout / Exit", 0

strAdminHeader   BYTE "ADMIN CONTROL PANEL (TIER 3)", 0
strAdminOpt1     BYTE "[1] Create New Account", 0
strAdminOpt2     BYTE "[2] Unlock Locked Account", 0
strAdminOpt3     BYTE "[3] List All Accounts", 0
strAdminOpt4     BYTE "[4] View Vault Cash & System Stats", 0
strAdminOpt5     BYTE "[5] Exit Admin Panel", 0

strPromptChoice  BYTE "Enter your choice: ", 0
strBalDisp       BYTE "Current Balance: PKR ", 0
strWdrPrompt     BYTE "Enter Withdrawal Amount (Multiple of 500 PKR): ", 0
strDepPrompt     BYTE "Enter Deposit Amount (PKR): ", 0
strXfrAccPrompt  BYTE "Enter Target Account Number: ", 0
strXfrAmtPrompt  BYTE "Enter Transfer Amount (PKR): ", 0

strPinOldPrompt  BYTE "Enter CURRENT 4-digit PIN: ", 0
strPinNewPrompt  BYTE "Enter NEW 4-digit PIN: ", 0
strPinCnfPrompt  BYTE "Re-enter NEW 4-digit PIN: ", 0
strPinMismatch   BYTE "Error: New PIN entries do not match!", 0
strPinSuccess    BYTE "PIN changed successfully!", 0
strShortPin      BYTE "Error: PIN must be 4 digits.", 0
strInvalidInput  BYTE "Invalid input. Please try again.", 0

strDispHeader    BYTE "--- Dispensing Cash Notes ---", 0
strNoteDisp      BYTE " Note(s)", 0
strPKR           BYTE "PKR ", 0
strTimes         BYTE " x ", 0
strStockLabel    BYTE "  Stock: ", 0
strDispLabel     BYTE "  Dispensed: ", 0

strNewAccPrompt  BYTE "Enter New 8-digit Account Number: ", 0
strNewNamePrompt BYTE "Enter Account Holder Name: ", 0
strNewBalPrompt  BYTE "Enter Initial Deposit (PKR): ", 0
strNewPinPrompt  BYTE "Set 4-digit PIN for New Account: ", 0
strAccCreated    BYTE "Account created successfully!", 0
strAccExists     BYTE "Error: Account number already exists!", 0
strDbFull        BYTE "Error: Maximum account capacity reached!", 0

strUnlockPrompt  BYTE "Enter Account Number to Unlock: ", 0
strUnlockedMsg   BYTE "Account unlocked successfully!", 0

strVaultTitle    BYTE "ATM Vault Reserve & Hardware Status", 0
strTotalVault    BYTE "Total Cash in Vault: PKR ", 0
strTotalTxVol    BYTE "64-Bit Cumulative System Volume: PKR ", 0

strReceiptGen    BYTE "Receipt generated successfully: ", 0
strTxSuccess     BYTE "Transaction Successful!", 0
strGoodbye       BYTE "Thank you for banking with us. Goodbye!", 0
strInvalidOpt    BYTE "Invalid Choice! Please enter a valid option.", 0

strStmtHeader    BYTE "MINI STATEMENT", 0
strNoStmt        BYTE "No transactions found for this account.", 0

strAdminSetPin   BYTE "Set new 4-digit Admin PIN: ", 0
strAdminCnfPin   BYTE "Re-enter Admin PIN: ", 0
strAdminLocked   BYTE "Error: Admin login is locked for this session.", 0
strTimeout       BYTE "Session expired. Logging out.", 0

strErrFunds      BYTE "Transaction Failed: Insufficient funds.", 0
strErrOverflow   BYTE "Transaction Failed: Amount exceeds limit/overflow.", 0
strErrInvalid    BYTE "Transaction Failed: Invalid amount entered.", 0
strErrDenom      BYTE "Transaction Failed: Amount must be multiple of PKR 500.", 0
strErrDailyLim   BYTE "Transaction Failed: Exceeds daily limit PKR 25000/day.", 0
strErrSelfXfr    BYTE "Transaction Failed: Cannot transfer funds to self.", 0
strErrTarget     BYTE "Transaction Failed: Target account not found.", 0
strErrChecksum   BYTE "FATAL: Database corrupt. Delete accounts.dat and restart.", 0
strErrVaultLow   BYTE "Transaction Failed: ATM vault cannot dispense amount.", 0
strErrFile       BYTE "Transaction Failed: File I/O error.", 0

; Audit tags
tagDep     BYTE "DEP", 0
tagWdr     BYTE "WDR", 0
tagLock    BYTE "LOCKED", 0
tagXfrOut  BYTE "XFR_OUT", 0
tagXfrIn   BYTE "XFR_IN", 0
tagPinChg  BYTE "PIN_CHG", 0

; Result strings
resOK          BYTE "OK", 0
resFailFunds   BYTE "FAIL_FUNDS", 0
resFailLimit   BYTE "FAIL_LIMIT", 0
resFailDenom   BYTE "FAIL_DENOM", 0
resFailVault   BYTE "FAIL_VAULT", 0
resLocked      BYTE "LOCKED", 0

; Error table for mShowError
errTable DWORD OFFSET strTxSuccess      ; 0 OK
         DWORD OFFSET strErrTarget      ; 1 E_NOT_FOUND
         DWORD OFFSET strLoginFailed    ; 2 E_BAD_PIN
         DWORD OFFSET strAccLocked      ; 3 E_LOCKED
         DWORD OFFSET strErrFunds       ; 4 E_INSUFFICIENT
         DWORD OFFSET strErrDailyLim    ; 5 E_DAILY_LIMIT
         DWORD OFFSET strErrDenom       ; 6 E_BAD_DENOM
         DWORD OFFSET strErrInvalid     ; 7 E_INVALID_AMT
         DWORD OFFSET strErrOverflow    ; 8 E_OVERFLOW
         DWORD OFFSET strErrFile        ; 9 E_FILE
         DWORD OFFSET strErrSelfXfr     ; 10 E_SAME_ACCOUNT
         DWORD OFFSET strTimeout        ; 11 E_TIMEOUT
         DWORD OFFSET strErrVaultLow    ; 12 E_VAULT_LOW
         DWORD OFFSET strAdminLocked    ; 13 E_ADMIN_LOCKED

; =============================================================================
; PROTOTYPES
; =============================================================================

.code

ReadMaskedPin     PROTO pBuf:DWORD, maxLen:DWORD
HashPin           PROTO pPin:DWORD, salt:DWORD
NumToStr          PROTO num:DWORD, pOut:DWORD

AppendChar        PROTO charVal:DWORD
AppendString      PROTO pStr:DWORD
AppendDWord       PROTO num:DWORD
AppendTwoDigit    PROTO val:DWORD
AppendDateTime    PROTO

UInt64ToStr       PROTO hiVal:DWORD, loVal:DWORD, pOut:DWORD
GetNextTxId       PROTO
LogTransaction    PROTO txId:DWORD, accNo:DWORD, pTag:DWORD, amount:DWORD, balAfter:DWORD, pResult:DWORD
GenerateReceipt   PROTO txId:DWORD, accNo:DWORD, pTag:DWORD, amount:DWORD, balAfter:DWORD

CheckDailyLimit   PROTO pAcc:DWORD, amount:DWORD
ClearPlanned      PROTO
CheckDispense     PROTO amount:DWORD, denomIdx:DWORD
DispensePlanned   PROTO

ParseAmount       PROTO pStr:DWORD, pOut:DWORD
ReadAmount        PROTO pPrompt:DWORD, pOut:DWORD

SetColorUI        PROTO textColor:DWORD
EnsureAdminPin    PROTO
CheckSessionTimeout PROTO

LineMatchesAccount PROTO pLine:DWORD
CopyStatementLine  PROTO pLine:DWORD, pDest:DWORD

SaveAccounts      PROTO

; Gotoxy / boxed UI helpers
StrLen            PROTO pStr:DWORD
SetCursor         PROTO xPos:DWORD, yPos:DWORD
DrawHLine         PROTO xPos:DWORD, yPos:DWORD, lineLen:DWORD, fillChar:DWORD
DrawVLine         PROTO xPos:DWORD, yPos:DWORD, lineLen:DWORD, fillChar:DWORD
DrawBox           PROTO xPos:DWORD, yPos:DWORD, boxW:DWORD, boxH:DWORD
PrintCentered     PROTO pStr:DWORD, xPos:DWORD, yPos:DWORD, boxWidth:DWORD
BuildConfirmMsg   PROTO pPrefix:DWORD, amount:DWORD
ShowMessageBox    PROTO pMsg:DWORD
ShowMsgBoxAsk     PROTO pText:DWORD, pCaption:DWORD, uType:DWORD

; =============================================================================
; MAIN
; =============================================================================

main PROC
    call LoadOrCreateAccounts
    call ShowSplashScreen
    call ReadChar
    call Clrscr
    call EnsureAdminPin

LoginLoop:
    INVOKE SetColorUI, COLOR_DEFAULT
    call Clrscr

    INVOKE SetColorUI, COLOR_TITLE
    mov edx, OFFSET lineBorder
    call WriteString
    call Crlf

    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, OFFSET strAccPrompt
    call WriteString
    call ReadDec
    mov ebx, eax
    call Crlf

    cmp ebx, ADMIN_ACC_NO
    je AdminLogin

    call FindAccount
    mov currentAccIdx, eax

    mov edx, OFFSET strPinPrompt
    call WriteString
    INVOKE ReadMaskedPin, OFFSET rawPinBuffer, 4
    mov enteredPinLen, eax
    call Crlf

    cmp currentAccIdx, -1
    je AuthUnknown

    mov eax, currentAccIdx
    mov ebx, SIZEOF ACCOUNT
    mul ebx
    lea esi, [accounts + eax]

    cmp enteredPinLen, MIN_PIN_LEN
    jne AuthFailedMatch

    INVOKE HashPin, OFFSET rawPinBuffer, [esi].ACCOUNT.salt
    cmp eax, [esi].ACCOUNT.pinHash
    jne AuthFailedMatch

    test [esi].ACCOUNT.status, 1
    jnz AccountIsLocked

    mov [esi].ACCOUNT.failCount, 0
    call SaveAccounts
    call WipePinBuffers

    INVOKE GetTickCount
    mov lastActivity, eax

    jmp AtmMenuLoop

AuthUnknown:
    INVOKE HashPin, OFFSET rawPinBuffer, dummySalt
    call WipePinBuffers
    INVOKE ShowMessageBox, OFFSET strLoginFailed
    jmp LoginLoop

AuthFailedMatch:
    test [esi].ACCOUNT.status, 1
    jnz AuthFailedGeneric

    inc [esi].ACCOUNT.failCount
    cmp [esi].ACCOUNT.failCount, 3
    jb AuthFailedGeneric

    or [esi].ACCOUNT.status, 1

    INVOKE GetNextTxId
    mov ebx, eax
    INVOKE LogTransaction, ebx, [esi].ACCOUNT.accNo, OFFSET tagLock, 0, [esi].ACCOUNT.balance, OFFSET resLocked

    call SaveAccounts

AuthFailedGeneric:
    call WipePinBuffers
    INVOKE ShowMessageBox, OFFSET strLoginFailed
    jmp LoginLoop

AccountIsLocked:
    call WipePinBuffers
    INVOKE ShowMessageBox, OFFSET strAccLocked
    jmp LoginLoop

AdminLogin:
    call EnsureAdminPin

    cmp adminLocked, 1
    je AdminLockedNow

    mov edx, OFFSET strPinPrompt
    call WriteString
    INVOKE ReadMaskedPin, OFFSET rawPinBuffer, 4
    mov enteredPinLen, eax
    call Crlf

    cmp enteredPinLen, MIN_PIN_LEN
    jne AdminAuthFail

    INVOKE HashPin, OFFSET rawPinBuffer, dbHeader.adminSalt
    cmp eax, dbHeader.adminPinHash
    jne AdminAuthFail

    mov adminFailCount, 0
    call WipePinBuffers

    INVOKE GetTickCount
    mov lastActivity, eax

    jmp AdminMenuLoop

AdminAuthFail:
    inc adminFailCount
    cmp adminFailCount, 3
    jb AdminGeneric

    mov adminLocked, 1

AdminGeneric:
    call WipePinBuffers
    INVOKE ShowMessageBox, OFFSET strLoginFailed
    jmp LoginLoop

AdminLockedNow:
    INVOKE ShowMessageBox, OFFSET strAdminLocked
    jmp LoginLoop

AtmMenuLoop:
    call ShowMainMenu
    call ReadChar
    mov menuChoice, al

    call CheckSessionTimeout
    cmp eax, E_TIMEOUT
    je SessionTimeout

    INVOKE GetTickCount
    mov lastActivity, eax

    mov al, menuChoice
    call WriteChar

    cmp al, '1'
    je ExecBalance
    cmp al, '2'
    je ExecWithdraw
    cmp al, '3'
    je ExecDeposit
    cmp al, '4'
    je ExecTransfer
    cmp al, '5'
    je ExecChangePin
    cmp al, '6'
    je ExecStatement
    cmp al, '7'
    je ExecLogout

    INVOKE ShowMessageBox, OFFSET strInvalidOpt
    jmp AtmMenuLoop

AdminMenuLoop:
    call ShowAdminMenu
    call ReadChar
    mov menuChoice, al

    call CheckSessionTimeout
    cmp eax, E_TIMEOUT
    je SessionTimeout

    INVOKE GetTickCount
    mov lastActivity, eax

    mov al, menuChoice
    call WriteChar

    cmp al, '1'
    je ExecAdminCreate
    cmp al, '2'
    je ExecAdminUnlock
    cmp al, '3'
    je ExecAdminList
    cmp al, '4'
    je ExecAdminVault
    cmp al, '5'
    je LoginLoop

    INVOKE ShowMessageBox, OFFSET strInvalidOpt
    jmp AdminMenuLoop

SessionTimeout:
    INVOKE ShowMessageBox, OFFSET strTimeout
    mov currentAccIdx, -1
    jmp LoginLoop

ExecBalance:
    call DoBalanceInquiry
    jmp AtmMenuLoop

ExecWithdraw:
    call DoWithdrawal
    jmp AtmMenuLoop

ExecDeposit:
    call DoDeposit
    jmp AtmMenuLoop

ExecTransfer:
    call DoTransfer
    jmp AtmMenuLoop

ExecChangePin:
    call DoChangePin
    jmp AtmMenuLoop

ExecStatement:
    call DoMiniStatement
    jmp AtmMenuLoop

ExecAdminCreate:
    call DoCreateAccount
    jmp AdminMenuLoop

ExecAdminUnlock:
    call DoUnlockAccount
    jmp AdminMenuLoop

ExecAdminList:
    call DoListAccounts
    jmp AdminMenuLoop

ExecAdminVault:
    call DoVaultStatus
    jmp AdminMenuLoop

ExecLogout:
    call Crlf
    INVOKE SetColorUI, COLOR_SUCCESS
    mov edx, OFFSET strGoodbye
    call WriteString
    call Crlf
    call Crlf
    INVOKE SetColorUI, COLOR_DEFAULT
    exit

main ENDP

; =============================================================================
; GOTOXY / BOXED SCREEN HELPERS
; =============================================================================

StrLen PROC USES ecx, pStr:DWORD
    mov ecx, pStr
    xor eax, eax

sl_loop:
    cmp BYTE PTR [ecx], 0
    je sl_done

    inc ecx
    inc eax
    jmp sl_loop

sl_done:
    ret
StrLen ENDP


SetCursor PROC USES eax ebx edx, xPos:DWORD, yPos:DWORD
    mov eax, xPos
    mov ebx, yPos

    and eax, 0FFh
    and ebx, 0FFh

    shl ebx, 8
    or eax, ebx

    mov edx, eax
    call Gotoxy
    ret
SetCursor ENDP


DrawHLine PROC USES eax ebx ecx edx, xPos:DWORD, yPos:DWORD, lineLen:DWORD, fillChar:DWORD
LOCAL curX:DWORD
LOCAL remaining:DWORD

    mov eax, xPos
    mov curX, eax
    mov eax, lineLen
    mov remaining, eax

    cmp remaining, 0
    jz dhl_done

dhl_loop:
    INVOKE SetCursor, curX, yPos

    mov eax, fillChar
    call WriteChar

    inc curX
    dec remaining

    cmp remaining, 0
    jnz dhl_loop

dhl_done:
    ret
DrawHLine ENDP


DrawVLine PROC USES eax ebx ecx edx, xPos:DWORD, yPos:DWORD, lineLen:DWORD, fillChar:DWORD
LOCAL curY:DWORD
LOCAL remaining:DWORD

    mov eax, yPos
    mov curY, eax
    mov eax, lineLen
    mov remaining, eax

    cmp remaining, 0
    jz dvl_done

dvl_loop:
    INVOKE SetCursor, xPos, curY

    mov eax, fillChar
    call WriteChar

    inc curY
    dec remaining

    cmp remaining, 0
    jnz dvl_loop

dvl_done:
    ret
DrawVLine ENDP


DrawBox PROC USES eax ebx ecx edx, xPos:DWORD, yPos:DWORD, boxW:DWORD, boxH:DWORD
LOCAL bottomY:DWORD
LOCAL rightX:DWORD
LOCAL innerY:DWORD
LOCAL innerH:DWORD

    mov eax, yPos
    add eax, boxH
    dec eax
    mov bottomY, eax

    mov eax, xPos
    add eax, boxW
    dec eax
    mov rightX, eax

    INVOKE DrawHLine, xPos, yPos, boxW, CHAR_MINUS
    INVOKE DrawHLine, xPos, bottomY, boxW, CHAR_MINUS

    mov eax, boxH
    sub eax, 2
    mov innerH, eax

    test eax, eax
    jz db_corners

    mov eax, yPos
    inc eax
    mov innerY, eax

    INVOKE DrawVLine, xPos, innerY, innerH, CHAR_PIPE
    INVOKE DrawVLine, rightX, innerY, innerH, CHAR_PIPE

db_corners:
    INVOKE SetCursor, xPos, yPos
    mov al, CHAR_PLUS
    call WriteChar

    INVOKE SetCursor, rightX, yPos
    mov al, CHAR_PLUS
    call WriteChar

    INVOKE SetCursor, xPos, bottomY
    mov al, CHAR_PLUS
    call WriteChar

    INVOKE SetCursor, rightX, bottomY
    mov al, CHAR_PLUS
    call WriteChar

    ret
DrawBox ENDP


PrintCentered PROC USES eax ebx ecx edx, pStr:DWORD, xPos:DWORD, yPos:DWORD, boxWidth:DWORD
LOCAL strLenVal:DWORD
LOCAL startX:DWORD

    INVOKE StrLen, pStr
    mov strLenVal, eax

    mov eax, boxWidth
    sub eax, strLenVal
    jc pc_left

    shr eax, 1
    add eax, xPos
    mov startX, eax
    jmp pc_set

pc_left:
    mov eax, xPos
    mov startX, eax

pc_set:
    INVOKE SetCursor, startX, yPos

    mov edx, pStr
    call WriteString

    ret
PrintCentered ENDP


BuildConfirmMsg PROC USES eax, pPrefix:DWORD, amount:DWORD
    mov appendPtr, OFFSET confirmMsg

    INVOKE AppendString, pPrefix
    INVOKE AppendDWord, amount
    INVOKE AppendString, OFFSET strConfirmSuffix

    mov eax, appendPtr
    mov BYTE PTR [eax], 0

    ret
BuildConfirmMsg ENDP


ShowMessageBox PROC pMsg:DWORD
    call Clrscr

    INVOKE SetColorUI, COLOR_PROMPT
    INVOKE DrawBox, CONFIRM_LEFT, CONFIRM_TOP, CONFIRM_WIDTH, MSGBOX_HEIGHT

    INVOKE PrintCentered, pMsg, CONFIRM_LEFT, 8, CONFIRM_WIDTH

    INVOKE SetColorUI, COLOR_DEFAULT
    INVOKE SetCursor, 10, 10
    call WaitMsg

    ret
ShowMessageBox ENDP

; =============================================================================
; UI PROCEDURES
; =============================================================================

SetColorUI PROC textColor:DWORD
    mov eax, textColor
    call SetTextColor
    ret
SetColorUI ENDP

ShowSplashScreen PROC
    INVOKE SetColorUI, COLOR_TITLE
    call Clrscr

    INVOKE DrawBox, SPLASH_LEFT, SPLASH_TOP, SPLASH_WIDTH, SPLASH_HEIGHT

    INVOKE SetColorUI, COLOR_TITLE
    INVOKE PrintCentered, OFFSET strSplashTitle, SPLASH_LEFT, 7, SPLASH_WIDTH

    INVOKE SetColorUI, COLOR_PROMPT
    INVOKE PrintCentered, OFFSET strSplashSub, SPLASH_LEFT, 9, SPLASH_WIDTH
    INVOKE PrintCentered, OFFSET strPressKey, SPLASH_LEFT, 11, SPLASH_WIDTH

    ret
ShowSplashScreen ENDP

ShowMainMenu PROC
    call Clrscr

    INVOKE SetColorUI, COLOR_TITLE
    INVOKE DrawBox, BOX_LEFT, BOX_TOP, BOX_WIDTH, MENU_HEIGHT

    INVOKE PrintCentered, OFFSET strMenuHeader, BOX_LEFT, 3, BOX_WIDTH

    INVOKE SetColorUI, COLOR_DEFAULT
    INVOKE DrawHLine, 6, 4, 58, CHAR_MINUS

    INVOKE SetCursor, 8, 6
    mov edx, OFFSET strMenuOpt1
    call WriteString

    INVOKE SetCursor, 8, 7
    mov edx, OFFSET strMenuOpt2
    call WriteString

    INVOKE SetCursor, 8, 8
    mov edx, OFFSET strMenuOpt3
    call WriteString

    INVOKE SetCursor, 8, 9
    mov edx, OFFSET strMenuOpt4
    call WriteString

    INVOKE SetCursor, 8, 10
    mov edx, OFFSET strMenuOpt5
    call WriteString

    INVOKE SetCursor, 8, 11
    mov edx, OFFSET strMenuOpt6
    call WriteString

    INVOKE SetCursor, 8, 12
    mov edx, OFFSET strMenuOpt7
    call WriteString

    INVOKE SetColorUI, COLOR_PROMPT
    INVOKE SetCursor, 8, 15
    mov edx, OFFSET strPromptChoice
    call WriteString

    INVOKE SetCursor, 27, 15

    ret
ShowMainMenu ENDP

ShowAdminMenu PROC
    call Clrscr

    INVOKE SetColorUI, COLOR_HEADER
    INVOKE DrawBox, BOX_LEFT, BOX_TOP, BOX_WIDTH, ADMIN_HEIGHT

    INVOKE PrintCentered, OFFSET strAdminHeader, BOX_LEFT, 3, BOX_WIDTH

    INVOKE SetColorUI, COLOR_DEFAULT
    INVOKE DrawHLine, 6, 4, 58, CHAR_MINUS

    INVOKE SetCursor, 8, 6
    mov edx, OFFSET strAdminOpt1
    call WriteString

    INVOKE SetCursor, 8, 7
    mov edx, OFFSET strAdminOpt2
    call WriteString

    INVOKE SetCursor, 8, 8
    mov edx, OFFSET strAdminOpt3
    call WriteString

    INVOKE SetCursor, 8, 9
    mov edx, OFFSET strAdminOpt4
    call WriteString

    INVOKE SetCursor, 8, 10
    mov edx, OFFSET strAdminOpt5
    call WriteString

    INVOKE SetColorUI, COLOR_PROMPT
    INVOKE SetCursor, 8, 12
    mov edx, OFFSET strPromptChoice
    call WriteString

    INVOKE SetCursor, 27, 12

    ret
ShowAdminMenu ENDP

; =============================================================================
; CORE UTILITIES
; =============================================================================

ReadMaskedPin PROC USES ebx ecx edi, pBuf:DWORD, maxLen:DWORD
    mov edi, pBuf
    xor ecx, ecx

rmp_read:
    call ReadChar

    cmp al, CHAR_ENTER
    je rmp_done

    cmp al, CHAR_BACKSPACE
    je rmp_back

    cmp al, '0'
    jb rmp_read

    cmp al, '9'
    ja rmp_read

    cmp ecx, maxLen
    jae rmp_read

    mov [edi + ecx], al
    inc ecx

    mov al, CHAR_STAR
    call WriteChar
    jmp rmp_read

rmp_back:
    test ecx, ecx
    jz rmp_read

    dec ecx

    mov al, CHAR_BACKSPACE
    call WriteChar
    mov al, ' '
    call WriteChar
    mov al, CHAR_BACKSPACE
    call WriteChar
    jmp rmp_read

rmp_done:
    mov BYTE PTR [edi + ecx], 0
    mov eax, ecx
    ret
ReadMaskedPin ENDP

HashPin PROC USES ebx esi, pPin:DWORD, salt:DWORD
    mov eax, 811C9DC5h
    xor eax, salt
    mov esi, pPin

hp_loop:
    movzx ebx, BYTE PTR [esi]
    test bl, bl
    jz hp_done

    xor eax, ebx
    imul eax, eax, 01000193h
    rol eax, 5

    inc esi
    jmp hp_loop

hp_done:
    ret
HashPin ENDP

FindAccount PROC USES ecx edi
    cld
    mov ecx, dbHeader.accountCount
    test ecx, ecx
    jz fa_notfound

    mov edi, OFFSET accNoIndex
    mov eax, ebx
    repne scasd
    jne fa_notfound

    mov eax, dbHeader.accountCount
    sub eax, ecx
    dec eax
    ret

fa_notfound:
    mov eax, -1
    ret
FindAccount ENDP

RebuildIndex PROC USES ebx ecx esi edi
    cld
    mov edi, OFFSET accNoIndex
    xor ecx, ecx

ri_loop:
    cmp ecx, dbHeader.accountCount
    jae ri_done

    mov eax, ecx
    mov ebx, SIZEOF ACCOUNT
    mul ebx
    lea esi, [accounts + eax]

    mov eax, [esi].ACCOUNT.accNo
    stosd

    inc ecx
    jmp ri_loop

ri_done:
    ret
RebuildIndex ENDP

WipePinBuffers PROC USES ecx edi
    cld
    xor eax, eax

    mov edi, OFFSET rawPinBuffer
    mov ecx, SIZEOF rawPinBuffer
    rep stosb

    mov edi, OFFSET pinConfirmBuf
    mov ecx, SIZEOF pinConfirmBuf
    rep stosb

    ret
WipePinBuffers ENDP

GetCurrentAccPtr PROC USES eax ebx
    mov eax, currentAccIdx
    mov ebx, SIZEOF ACCOUNT
    mul ebx
    lea esi, [accounts + eax]
    ret
GetCurrentAccPtr ENDP

GetTodayPacked PROC USES ebx ecx edx
    INVOKE GetLocalTime, ADDR sysTime

    movzx eax, sysTime.wYear
    imul eax, eax, 10000

    movzx ebx, sysTime.wMonth
    imul ebx, ebx, 100
    add eax, ebx

    movzx ebx, sysTime.wDay
    add eax, ebx

    ret
GetTodayPacked ENDP

ComputeChecksum PROC USES ebx ecx esi
    mov esi, OFFSET accounts

    mov eax, SIZEOF ACCOUNT
    imul eax, dbHeader.accountCount
    shr eax, 2
    mov ecx, eax

    xor eax, eax
    test ecx, ecx
    jz cs_done

cs_loop:
    rol eax, 3
    xor eax, [esi]
    add esi, 4
    loop cs_loop

cs_done:
    ret
ComputeChecksum ENDP

CheckDailyLimit PROC USES ebx esi, pAcc:DWORD, amount:DWORD
LOCAL today:DWORD
LOCAL base:DWORD

    mov esi, pAcc

    call GetTodayPacked
    mov today, eax

    cmp eax, [esi].ACCOUNT.lastWdrDate
    je cdl_same_day

    mov base, 0
    jmp cdl_add

cdl_same_day:
    mov eax, [esi].ACCOUNT.dailyWithdrawn
    mov base, eax

cdl_add:
    mov eax, base
    add eax, amount
    jc cdl_fail

    cmp eax, DAILY_LIMIT
    ja cdl_fail

    mov ecx, eax
    mov edx, today
    mov eax, OK
    ret

cdl_fail:
    mov eax, E_DAILY_LIMIT
    ret

CheckDailyLimit ENDP

; =============================================================================
; DISPENSER
; =============================================================================

ClearPlanned PROC USES ecx edi
    cld
    xor eax, eax
    mov edi, OFFSET denomPlanned
    mov ecx, DENOM_COUNT
    rep stosd
    ret
ClearPlanned ENDP

CheckDispense PROC USES ebx ecx edx, amount:DWORD, denomIdx:DWORD
LOCAL want:DWORD
LOCAL notes:DWORD
LOCAL remAmt:DWORD
LOCAL stock:DWORD
LOCAL noteVal:DWORD

    mov eax, amount
    test eax, eax
    jz cd_ok

    mov ecx, denomIdx
    cmp ecx, DENOM_COUNT
    jae cd_fail

    mov eax, ecx
    imul eax, eax, VAULT_COLS * 4
    mov ebx, vaultTable[eax + COL_VALUE * 4]
    mov noteVal, ebx

    mov eax, amount
    xor edx, edx
    div ebx
    mov want, eax
    mov remAmt, edx

    mov eax, ecx
    imul eax, eax, VAULT_COLS * 4
    mov ebx, vaultTable[eax + COL_STOCK * 4]
    mov stock, ebx

    mov eax, want
    cmp eax, stock
    jbe cd_use_want
    mov eax, stock

cd_use_want:
    mov notes, eax

    mov eax, notes
    mul noteVal

    mov ecx, amount
    sub ecx, eax
    mov remAmt, ecx

    mov ecx, denomIdx
    mov eax, notes
    mov denomPlanned[ecx * 4], eax

    mov eax, denomIdx
    inc eax
    INVOKE CheckDispense, remAmt, eax
    ret

cd_ok:
    mov eax, OK
    ret

cd_fail:
    mov eax, E_VAULT_LOW
    ret

CheckDispense ENDP

DispensePlanned PROC USES ebx ecx edx esi
LOCAL idx:DWORD
LOCAL count:DWORD
LOCAL noteVal:DWORD
LOCAL row:DWORD

    INVOKE SetColorUI, COLOR_TITLE
    mov edx, OFFSET strDispHeader
    call WriteString
    call Crlf

    mov idx, 0

dp_loop:
    mov eax, idx
    cmp eax, DENOM_COUNT
    jae dp_done

    mov ecx, eax
    mov eax, denomPlanned[ecx * 4]
    mov count, eax

    test eax, eax
    jz dp_next

    mov eax, ecx
    imul eax, eax, VAULT_COLS * 4
    mov row, eax

    mov ebx, vaultTable[row + COL_VALUE * 4]
    mov noteVal, ebx

    mov ebx, count
    mov eax, row
    sub vaultTable[eax + COL_STOCK * 4], ebx
    add vaultTable[eax + COL_DISP * 4], ebx

    INVOKE SetColorUI, COLOR_SUCCESS

    mov edx, OFFSET strPKR
    call WriteString

    mov eax, noteVal
    call WriteDec

    mov edx, OFFSET strTimes
    call WriteString

    mov eax, count
    call WriteDec

    mov edx, OFFSET strNoteDisp
    call WriteString
    call Crlf

dp_next:
    inc idx
    jmp dp_loop

dp_done:
    ret
DispensePlanned ENDP

; =============================================================================
; AMOUNT INPUT
; =============================================================================

ParseAmount PROC USES ebx ecx edx esi edi, pStr:DWORD, pOut:DWORD
    mov esi, pStr
    xor eax, eax
    xor ebx, ebx
    mov edi, 10

pa_loop:
    movzx ecx, BYTE PTR [esi]
    test cl, cl
    jz pa_check

    cmp cl, '0'
    jb pa_invalid

    cmp cl, '9'
    ja pa_invalid

    sub cl, '0'

    mul edi
    test edx, edx
    jnz pa_overflow

    add eax, ecx
    jc pa_overflow

    inc ebx
    inc esi
    jmp pa_loop

pa_check:
    test ebx, ebx
    jz pa_invalid

    mov edi, pOut
    mov [edi], eax
    mov eax, OK
    ret

pa_invalid:
    mov eax, E_INVALID_AMT
    ret

pa_overflow:
    mov eax, E_OVERFLOW
    ret

ParseAmount ENDP

ReadAmount PROC pPrompt:DWORD, pOut:DWORD
    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, pPrompt
    call WriteString

    mov edx, OFFSET inputBuf
    mov ecx, SIZEOF inputBuf - 1
    call ReadString
    call Crlf

    INVOKE ParseAmount, OFFSET inputBuf, pOut
    ret
ReadAmount ENDP

; =============================================================================
; STRING / DATE / NUMBER APPEND HELPERS
; =============================================================================

AppendChar PROC USES edi, charVal:DWORD
    mov eax, charVal
    mov edi, appendPtr
    mov [edi], al
    inc edi
    mov appendPtr, edi
    ret
AppendChar ENDP

AppendString PROC USES esi edi, pStr:DWORD
    mov esi, pStr
    mov edi, appendPtr

as_loop:
    mov al, [esi]
    test al, al
    jz as_done

    mov [edi], al
    inc esi
    inc edi
    jmp as_loop

as_done:
    mov appendPtr, edi
    ret
AppendString ENDP

AppendDWord PROC USES ebx ecx edx edi, num:DWORD
    mov eax, num
    mov ebx, 10
    xor ecx, ecx

ad_div:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz ad_div

    mov edi, appendPtr

ad_pop:
    pop edx
    add dl, '0'
    mov [edi], dl
    inc edi
    loop ad_pop

    mov appendPtr, edi
    ret
AppendDWord ENDP

AppendTwoDigit PROC USES ebx ecx edx, val:DWORD
    mov eax, val
    mov ebx, 10
    xor edx, edx
    div ebx

    push edx
    mov ecx, eax
    INVOKE AppendChar, ecx

    pop ecx
    INVOKE AppendChar, ecx

    ret
AppendTwoDigit ENDP

AppendDateTime PROC USES eax ecx edx
    INVOKE GetLocalTime, ADDR sysTime

    movzx eax, sysTime.wYear
    INVOKE AppendDWord, eax

    INVOKE AppendChar, CHAR_MINUS

    movzx eax, sysTime.wMonth
    INVOKE AppendTwoDigit, eax

    INVOKE AppendChar, CHAR_MINUS

    movzx eax, sysTime.wDay
    INVOKE AppendTwoDigit, eax

    INVOKE AppendChar, CHAR_SPACE

    movzx eax, sysTime.wHour
    INVOKE AppendTwoDigit, eax

    INVOKE AppendChar, CHAR_COLON

    movzx eax, sysTime.wMinute
    INVOKE AppendTwoDigit, eax

    INVOKE AppendChar, CHAR_COLON

    movzx eax, sysTime.wSecond
    INVOKE AppendTwoDigit, eax

    ret
AppendDateTime ENDP

UInt64ToStr PROC USES ebx ecx edx esi edi, hiVal:DWORD, loVal:DWORD, pOut:DWORD
LOCAL qHi:DWORD
LOCAL qLo:DWORD
LOCAL remDigit:DWORD

    mov edi, pOut

    mov eax, hiVal
    or eax, eax
    jnz u64_start

    mov eax, loVal
    or eax, eax
    jnz u64_start

    mov BYTE PTR [edi], '0'
    mov BYTE PTR [edi + 1], 0
    ret

u64_start:
    xor ecx, ecx
    mov esi, 10

u64_loop:
    mov eax, hiVal
    xor edx, edx
    div esi
    mov qHi, eax

    mov eax, loVal
    div esi
    mov qLo, eax
    mov remDigit, edx

    mov eax, remDigit
    add al, '0'
    movzx eax, al
    push eax
    inc ecx

    mov eax, qHi
    mov hiVal, eax

    mov eax, qLo
    mov loVal, eax

    or eax, eax
    jnz u64_loop

    mov eax, qHi
    or eax, eax
    jnz u64_loop

u64_pop:
    pop eax
    mov [edi], al
    inc edi
    loop u64_pop

    mov BYTE PTR [edi], 0
    ret

UInt64ToStr ENDP

NumToStr PROC USES ebx ecx edx edi, num:DWORD, pOut:DWORD
    mov eax, num
    mov edi, pOut
    xor ecx, ecx
    mov ebx, 10

nts_loop:
    xor edx, edx
    div ebx
    add dl, '0'
    push edx
    inc ecx
    test eax, eax
    jnz nts_loop

nts_pop:
    pop edx
    mov [edi], dl
    inc edi
    loop nts_pop

    mov BYTE PTR [edi], 0
    mov eax, edi
    ret
NumToStr ENDP

GetNextTxId PROC
    mov eax, dbHeader.txIdCounter
    inc dbHeader.txIdCounter
    ret
GetNextTxId ENDP

; =============================================================================
; LOGGING AND RECEIPTS
; =============================================================================

LogTransaction PROC USES ebx ecx edx esi edi, txId:DWORD, accNo:DWORD, pTag:DWORD, amount:DWORD, balAfter:DWORD, pResult:DWORD
LOCAL logLen:DWORD
LOCAL hFile:DWORD

    mov appendPtr, OFFSET logBuffer

    INVOKE AppendDWord, txId
    INVOKE AppendChar, CHAR_PIPE

    INVOKE AppendDWord, accNo
    INVOKE AppendChar, CHAR_PIPE

    INVOKE AppendString, pTag
    INVOKE AppendChar, CHAR_PIPE

    INVOKE AppendDWord, amount
    INVOKE AppendChar, CHAR_PIPE

    INVOKE AppendDWord, balAfter
    INVOKE AppendChar, CHAR_PIPE

    INVOKE AppendDateTime
    INVOKE AppendChar, CHAR_PIPE

    INVOKE AppendString, pResult

    INVOKE AppendChar, CHAR_CR
    INVOKE AppendChar, CHAR_LF

    mov edi, appendPtr
    sub edi, OFFSET logBuffer
    mov logLen, edi

    INVOKE CreateFile, OFFSET fnLog, GENERIC_WRITE, FILE_SHARE_BOTH, 0, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0
    cmp eax, INVALID_HANDLE_VALUE
    je lt_done

    mov hFile, eax

    INVOKE SetFilePointer, hFile, 0, 0, FILE_END
    INVOKE WriteFile, hFile, OFFSET logBuffer, logLen, OFFSET bytesWritten, 0
    INVOKE CloseHandle, hFile

lt_done:
    ret
LogTransaction ENDP

GenerateReceipt PROC USES ebx ecx edx esi edi, txId:DWORD, accNo:DWORD, pTag:DWORD, amount:DWORD, balAfter:DWORD
LOCAL rLen:DWORD
LOCAL rFile:DWORD
LOCAL fnReceipt[32]:BYTE

    lea edi, fnReceipt

    mov BYTE PTR [edi], 'r'
    mov BYTE PTR [edi + 1], 'c'
    mov BYTE PTR [edi + 2], 'p'
    mov BYTE PTR [edi + 3], 't'
    mov BYTE PTR [edi + 4], '_'
    add edi, 5

    INVOKE NumToStr, txId, edi
    mov edi, eax

    mov BYTE PTR [edi], '.'
    mov BYTE PTR [edi + 1], 't'
    mov BYTE PTR [edi + 2], 'x'
    mov BYTE PTR [edi + 3], 't'
    mov BYTE PTR [edi + 4], 0

    mov appendPtr, OFFSET logBuffer

    INVOKE AppendString, OFFSET lineBorder
    INVOKE AppendChar, CHAR_CR
    INVOKE AppendChar, CHAR_LF

    INVOKE AppendString, OFFSET strSplashTitle
    INVOKE AppendChar, CHAR_CR
    INVOKE AppendChar, CHAR_LF

    INVOKE AppendString, OFFSET lineBorder
    INVOKE AppendChar, CHAR_CR
    INVOKE AppendChar, CHAR_LF

    INVOKE AppendDWord, txId
    INVOKE AppendChar, CHAR_PIPE

    INVOKE AppendDWord, accNo
    INVOKE AppendChar, CHAR_PIPE

    INVOKE AppendString, pTag
    INVOKE AppendChar, CHAR_PIPE

    INVOKE AppendDWord, amount
    INVOKE AppendChar, CHAR_PIPE

    INVOKE AppendDWord, balAfter
    INVOKE AppendChar, CHAR_PIPE

    INVOKE AppendDateTime

    INVOKE AppendChar, CHAR_CR
    INVOKE AppendChar, CHAR_LF

    mov ecx, appendPtr
    sub ecx, OFFSET logBuffer
    mov rLen, ecx

    lea edx, fnReceipt
    call CreateOutputFile
    cmp eax, INVALID_HANDLE_VALUE
    je gr_done

    mov rFile, eax

    mov edx, OFFSET logBuffer
    mov ecx, rLen
    call WriteToFile

    mov eax, rFile
    call CloseFile

    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, OFFSET strReceiptGen
    call WriteString

    lea edx, fnReceipt
    call WriteString
    call Crlf

gr_done:
    ret
GenerateReceipt ENDP

; =============================================================================
; CUSTOMER BANKING OPERATIONS
; =============================================================================

DoBalanceInquiry PROC
    call Clrscr
    call GetCurrentAccPtr

    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, OFFSET strBalDisp
    call WriteString

    INVOKE SetColorUI, COLOR_SUCCESS
    mov eax, [esi].ACCOUNT.balance
    call WriteDec
    call Crlf
    call Crlf

    call WaitMsg
    ret
DoBalanceInquiry ENDP

DoWithdrawal PROC
LOCAL txAmount:DWORD
LOCAL newDaily:DWORD
LOCAL today:DWORD
LOCAL txId:DWORD
LOCAL pAcc:DWORD

    call Clrscr
    call GetCurrentAccPtr
    mov pAcc, esi

    INVOKE ReadAmount, OFFSET strWdrPrompt, ADDR txAmount
    cmp eax, E_OVERFLOW
    je wdr_overflow_err

    cmp eax, OK
    jne wdr_invalid

    mov eax, txAmount
    test eax, eax
    jz wdr_invalid

    xor edx, edx
    mov ebx, MIN_NOTE
    div ebx
    test edx, edx
    jnz wdr_denom_err

    mov esi, pAcc
    mov eax, txAmount
    cmp eax, [esi].ACCOUNT.balance
    ja wdr_insufficient

    INVOKE CheckDailyLimit, pAcc, txAmount
    cmp eax, OK
    jne wdr_limit_err

    mov newDaily, ecx
    mov today, edx

    call ClearPlanned
    INVOKE CheckDispense, txAmount, 0
    cmp eax, OK
    jne wdr_vault_err

    ; Confirmation before committing money or vault stock
    INVOKE BuildConfirmMsg, OFFSET strConfirmWdrPrefix, txAmount
    INVOKE ShowMsgBoxAsk, OFFSET confirmMsg, OFFSET strConfirmTitle, MB_CONFIRM_TYPE

    cmp ax, IDYES
    je wdr_confirm_yes
    cmp ax, 1
    je wdr_confirm_yes
    jmp wdr_cancel

wdr_confirm_yes:
    call Clrscr

    mov esi, pAcc

    mov eax, txAmount
    sub [esi].ACCOUNT.balance, eax

    mov eax, newDaily
    mov [esi].ACCOUNT.dailyWithdrawn, eax

    mov eax, today
    mov [esi].ACCOUNT.lastWdrDate, eax

    mov eax, txAmount
    add dbHeader.totalTxLow, eax
    adc dbHeader.totalTxHigh, 0

    INVOKE GetNextTxId
    mov txId, eax

    INVOKE LogTransaction, txId, [esi].ACCOUNT.accNo, OFFSET tagWdr, txAmount, [esi].ACCOUNT.balance, OFFSET resOK
    INVOKE GenerateReceipt, txId, [esi].ACCOUNT.accNo, OFFSET tagWdr, txAmount, [esi].ACCOUNT.balance

    call SaveAccounts

    call Crlf
    call DispensePlanned
    call Crlf

    INVOKE SetColorUI, COLOR_SUCCESS
    mov edx, OFFSET strTxSuccess
    call WriteString
    call Crlf

    call WaitMsg
    ret

wdr_cancel:
    INVOKE ShowMessageBox, OFFSET strCancelled
    ret

wdr_denom_err:
    mov esi, pAcc
    INVOKE GetNextTxId
    mov txId, eax
    INVOKE LogTransaction, txId, [esi].ACCOUNT.accNo, OFFSET tagWdr, txAmount, [esi].ACCOUNT.balance, OFFSET resFailDenom
    call SaveAccounts

    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_BAD_DENOM
    call Crlf
    call WaitMsg
    ret

wdr_insufficient:
    mov esi, pAcc
    INVOKE GetNextTxId
    mov txId, eax
    INVOKE LogTransaction, txId, [esi].ACCOUNT.accNo, OFFSET tagWdr, txAmount, [esi].ACCOUNT.balance, OFFSET resFailFunds
    call SaveAccounts

    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_INSUFFICIENT
    call Crlf
    call WaitMsg
    ret

wdr_limit_err:
    mov esi, pAcc
    INVOKE GetNextTxId
    mov txId, eax
    INVOKE LogTransaction, txId, [esi].ACCOUNT.accNo, OFFSET tagWdr, txAmount, [esi].ACCOUNT.balance, OFFSET resFailLimit
    call SaveAccounts

    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_DAILY_LIMIT
    call Crlf
    call WaitMsg
    ret

wdr_vault_err:
    mov esi, pAcc
    INVOKE GetNextTxId
    mov txId, eax
    INVOKE LogTransaction, txId, [esi].ACCOUNT.accNo, OFFSET tagWdr, txAmount, [esi].ACCOUNT.balance, OFFSET resFailVault
    call SaveAccounts

    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_VAULT_LOW
    call Crlf
    call WaitMsg
    ret

wdr_overflow_err:
    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_OVERFLOW
    call Crlf
    call WaitMsg
    ret

wdr_invalid:
    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_INVALID_AMT
    call Crlf
    call WaitMsg
    ret

DoWithdrawal ENDP

DoDeposit PROC
LOCAL txAmount:DWORD
LOCAL txId:DWORD
LOCAL pAcc:DWORD

    call Clrscr
    call GetCurrentAccPtr
    mov pAcc, esi

    INVOKE ReadAmount, OFFSET strDepPrompt, ADDR txAmount
    cmp eax, E_OVERFLOW
    je dep_overflow_err

    cmp eax, OK
    jne dep_invalid

    mov eax, txAmount
    test eax, eax
    jz dep_invalid

    cmp eax, MAX_DEPOSIT
    ja dep_cap_err

    mov esi, pAcc

    mov ebx, [esi].ACCOUNT.balance
    add ebx, txAmount
    jc dep_overflow_err

    mov [esi].ACCOUNT.balance, ebx

    mov eax, txAmount
    add dbHeader.totalTxLow, eax
    adc dbHeader.totalTxHigh, 0

    INVOKE GetNextTxId
    mov txId, eax

    INVOKE LogTransaction, txId, [esi].ACCOUNT.accNo, OFFSET tagDep, txAmount, [esi].ACCOUNT.balance, OFFSET resOK
    INVOKE GenerateReceipt, txId, [esi].ACCOUNT.accNo, OFFSET tagDep, txAmount, [esi].ACCOUNT.balance

    call SaveAccounts

    INVOKE SetColorUI, COLOR_SUCCESS
    mov edx, OFFSET strTxSuccess
    call WriteString
    call Crlf

    call WaitMsg
    ret

dep_cap_err:
    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_OVERFLOW
    call Crlf
    call WaitMsg
    ret

dep_overflow_err:
    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_OVERFLOW
    call Crlf
    call WaitMsg
    ret

dep_invalid:
    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_INVALID_AMT
    call Crlf
    call WaitMsg
    ret

DoDeposit ENDP

DoTransfer PROC
LOCAL targetIdx:DWORD
LOCAL txAmount:DWORD
LOCAL newDaily:DWORD
LOCAL today:DWORD
LOCAL txId:DWORD
LOCAL pSrc:DWORD
LOCAL pDst:DWORD
LOCAL srcSnap[64]:BYTE
LOCAL dstSnap[64]:BYTE

    call Clrscr
    call GetCurrentAccPtr
    mov pSrc, esi

    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, OFFSET strXfrAccPrompt
    call WriteString
    call ReadDec
    mov ebx, eax
    call Crlf

    cmp ebx, [esi].ACCOUNT.accNo
    je xfr_self_err

    call FindAccount
    cmp eax, -1
    je xfr_target_err

    mov targetIdx, eax

    INVOKE ReadAmount, OFFSET strXfrAmtPrompt, ADDR txAmount
    cmp eax, E_OVERFLOW
    je xfr_overflow_err

    cmp eax, OK
    jne xfr_invalid

    mov eax, txAmount
    test eax, eax
    jz xfr_invalid

    mov esi, pSrc
    cmp eax, [esi].ACCOUNT.balance
    ja xfr_insufficient

    mov eax, targetIdx
    mov ebx, SIZEOF ACCOUNT
    mul ebx
    lea edi, [accounts + eax]
    mov pDst, edi

    mov eax, [edi].ACCOUNT.balance
    add eax, txAmount
    jc xfr_overflow_err

    INVOKE CheckDailyLimit, pSrc, txAmount
    cmp eax, OK
    jne xfr_limit_err

    mov newDaily, ecx
    mov today, edx

    ; Confirmation before snapshot/commit
    INVOKE BuildConfirmMsg, OFFSET strConfirmXfrPrefix, txAmount
    INVOKE ShowMsgBoxAsk, OFFSET confirmMsg, OFFSET strConfirmTitle, MB_CONFIRM_TYPE

    cmp ax, IDYES
    je xfr_confirm_yes
    cmp ax, 1
    je xfr_confirm_yes
    jmp xfr_cancel

xfr_confirm_yes:
    call Clrscr

    ; Snapshot source using REP MOVSB
    mov esi, pSrc
    lea edi, srcSnap
    mov ecx, SIZEOF ACCOUNT
    cld
    rep movsb

    ; Snapshot destination using REP MOVSB
    mov esi, pDst
    lea edi, dstSnap
    mov ecx, SIZEOF ACCOUNT
    cld
    rep movsb

    ; Commit source
    mov esi, pSrc
    mov edi, pDst

    mov eax, txAmount
    sub [esi].ACCOUNT.balance, eax

    mov eax, newDaily
    mov [esi].ACCOUNT.dailyWithdrawn, eax

    mov eax, today
    mov [esi].ACCOUNT.lastWdrDate, eax

    ; Commit destination
    mov eax, txAmount
    add [edi].ACCOUNT.balance, eax

    ; 64-bit total
    mov eax, txAmount
    add dbHeader.totalTxLow, eax
    adc dbHeader.totalTxHigh, 0

    INVOKE GetNextTxId
    mov txId, eax

    call SaveAccounts
    cmp eax, OK
    jne xfr_rollback

    mov esi, pSrc
    mov edi, pDst

    INVOKE LogTransaction, txId, [esi].ACCOUNT.accNo, OFFSET tagXfrOut, txAmount, [esi].ACCOUNT.balance, OFFSET resOK
    INVOKE LogTransaction, txId, [edi].ACCOUNT.accNo, OFFSET tagXfrIn, txAmount, [edi].ACCOUNT.balance, OFFSET resOK

    INVOKE GenerateReceipt, txId, [esi].ACCOUNT.accNo, OFFSET tagXfrOut, txAmount, [esi].ACCOUNT.balance

    INVOKE SetColorUI, COLOR_SUCCESS
    mov edx, OFFSET strTxSuccess
    call WriteString
    call Crlf

    call WaitMsg
    ret

xfr_cancel:
    INVOKE ShowMessageBox, OFFSET strCancelled
    ret

xfr_rollback:
    dec dbHeader.txIdCounter

    mov eax, txAmount
    sub dbHeader.totalTxLow, eax
    sbb dbHeader.totalTxHigh, 0

    lea esi, srcSnap
    mov edi, pSrc
    mov ecx, SIZEOF ACCOUNT
    cld
    rep movsb

    lea esi, dstSnap
    mov edi, pDst
    mov ecx, SIZEOF ACCOUNT
    cld
    rep movsb

    INVOKE ShowMessageBox, OFFSET strErrFile
    ret

xfr_self_err:
    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_SAME_ACCOUNT
    call Crlf
    call WaitMsg
    ret

xfr_target_err:
    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_NOT_FOUND
    call Crlf
    call WaitMsg
    ret

xfr_insufficient:
    mov esi, pSrc
    INVOKE GetNextTxId
    mov txId, eax
    INVOKE LogTransaction, txId, [esi].ACCOUNT.accNo, OFFSET tagXfrOut, txAmount, [esi].ACCOUNT.balance, OFFSET resFailFunds
    call SaveAccounts

    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_INSUFFICIENT
    call Crlf
    call WaitMsg
    ret

xfr_overflow_err:
    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_OVERFLOW
    call Crlf
    call WaitMsg
    ret

xfr_limit_err:
    mov esi, pSrc
    INVOKE GetNextTxId
    mov txId, eax
    INVOKE LogTransaction, txId, [esi].ACCOUNT.accNo, OFFSET tagXfrOut, txAmount, [esi].ACCOUNT.balance, OFFSET resFailLimit
    call SaveAccounts

    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_DAILY_LIMIT
    call Crlf
    call WaitMsg
    ret

xfr_invalid:
    INVOKE SetColorUI, COLOR_ERROR
    mShowError E_INVALID_AMT
    call Crlf
    call WaitMsg
    ret

DoTransfer ENDP

DoChangePin PROC
LOCAL pAcc:DWORD

    call Clrscr
    call GetCurrentAccPtr
    mov pAcc, esi

    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, OFFSET strPinOldPrompt
    call WriteString

    INVOKE ReadMaskedPin, OFFSET rawPinBuffer, 4
    mov enteredPinLen, eax
    call Crlf

    mov esi, pAcc

    cmp enteredPinLen, MIN_PIN_LEN
    jne chg_bad_old

    INVOKE HashPin, OFFSET rawPinBuffer, [esi].ACCOUNT.salt
    cmp eax, [esi].ACCOUNT.pinHash
    jne chg_bad_old_count

    mov edx, OFFSET strPinNewPrompt
    call WriteString

    INVOKE ReadMaskedPin, OFFSET rawPinBuffer, 4
    mov enteredPinLen, eax
    call Crlf

    cmp enteredPinLen, MIN_PIN_LEN
    jne chg_mismatch

    mov edx, OFFSET strPinCnfPrompt
    call WriteString

    INVOKE ReadMaskedPin, OFFSET pinConfirmBuf, 4
    mov enteredPinLen, eax
    call Crlf

    cmp enteredPinLen, MIN_PIN_LEN
    jne chg_mismatch

    mov esi, OFFSET rawPinBuffer
    mov edi, OFFSET pinConfirmBuf
    mov ecx, MIN_PIN_LEN
    cld
    repe cmpsb
    jne chg_mismatch

    mov esi, pAcc

    INVOKE HashPin, OFFSET rawPinBuffer, [esi].ACCOUNT.salt
    mov [esi].ACCOUNT.pinHash, eax

    INVOKE GetNextTxId
    mov ebx, eax
    INVOKE LogTransaction, ebx, [esi].ACCOUNT.accNo, OFFSET tagPinChg, 0, [esi].ACCOUNT.balance, OFFSET resOK

    call SaveAccounts
    call WipePinBuffers

    INVOKE ShowMessageBox, OFFSET strPinSuccess
    ret

chg_bad_old_count:
    mov esi, pAcc

    test [esi].ACCOUNT.status, 1
    jnz chg_bad_old

    inc [esi].ACCOUNT.failCount
    cmp [esi].ACCOUNT.failCount, 3
    jb chg_bad_old

    or [esi].ACCOUNT.status, 1

    INVOKE GetNextTxId
    mov ebx, eax
    INVOKE LogTransaction, ebx, [esi].ACCOUNT.accNo, OFFSET tagLock, 0, [esi].ACCOUNT.balance, OFFSET resLocked

    call SaveAccounts

chg_bad_old:
    call WipePinBuffers
    INVOKE ShowMessageBox, OFFSET strLoginFailed
    ret

chg_mismatch:
    call WipePinBuffers
    INVOKE ShowMessageBox, OFFSET strPinMismatch
    ret

DoChangePin ENDP

; =============================================================================
; MINI STATEMENT
; =============================================================================

DoMiniStatement PROC
LOCAL bytesRead:DWORD
LOCAL lineStart:DWORD
LOCAL pScan:DWORD

    call Clrscr
    call GetCurrentAccPtr

    INVOKE NumToStr, [esi].ACCOUNT.accNo, OFFSET accFilter

    mov stmtCount, 0

    mov edx, OFFSET fnLog
    call OpenInputFile
    cmp eax, INVALID_HANDLE_VALUE
    je stmt_empty

    mov ebx, eax

    mov edx, OFFSET stmtBuffer
    mov ecx, SIZEOF stmtBuffer - 1
    call ReadFromFile
    jc stmt_empty

    mov BYTE PTR stmtBuffer[eax], 0
    mov bytesRead, eax

    mov eax, ebx
    call CloseFile

    mov esi, OFFSET stmtBuffer
    mov pScan, esi

stmt_scan:
    mov esi, pScan
    mov lineStart, esi

stmt_find:
    mov al, [esi]
    test al, al
    jz stmt_display

    cmp al, CHAR_LF
    je stmt_process

    inc esi
    jmp stmt_find

stmt_process:
    mov BYTE PTR [esi], 0
    inc esi
    mov pScan, esi

    INVOKE LineMatchesAccount, lineStart
    test eax, eax
    jz stmt_scan

    cmp stmtCount, STMT_MAX
    jb stmt_no_shift

    mov esi, OFFSET stmtLines
    add esi, STMT_LINE_LEN
    mov edi, OFFSET stmtLines
    mov ecx, (STMT_MAX - 1) * STMT_LINE_LEN
    cld
    rep movsb

    mov stmtCount, STMT_MAX - 1

stmt_no_shift:
    mov eax, stmtCount
    imul eax, eax, STMT_LINE_LEN
    mov edi, OFFSET stmtLines
    add edi, eax

    INVOKE CopyStatementLine, lineStart, edi

    inc stmtCount
    jmp stmt_scan

stmt_display:
    cmp stmtCount, 0
    je stmt_empty_msg

    INVOKE SetColorUI, COLOR_TITLE
    mov edx, OFFSET lineBorder
    call WriteString
    call Crlf

    mov edx, OFFSET strStmtHeader
    call WriteString
    call Crlf

    mov edx, OFFSET lineBorder
    call WriteString
    call Crlf

    xor ecx, ecx

stmt_disp_loop:
    cmp ecx, stmtCount
    jae stmt_disp_done

    push ecx

    INVOKE SetColorUI, COLOR_DEFAULT

    mov eax, ecx
    imul eax, eax, STMT_LINE_LEN
    mov edx, OFFSET stmtLines
    add edx, eax
    call WriteString
    call Crlf

    pop ecx
    inc ecx
    jmp stmt_disp_loop

stmt_disp_done:
    call Crlf
    call WaitMsg
    ret

stmt_empty:
    INVOKE ShowMessageBox, OFFSET strNoStmt
    ret

stmt_empty_msg:
    INVOKE ShowMessageBox, OFFSET strNoStmt
    ret

DoMiniStatement ENDP

LineMatchesAccount PROC USES esi edi ecx edx, pLine:DWORD
LOCAL fLen:DWORD
LOCAL fieldStart:DWORD

    mov edi, OFFSET accFilter
    xor ecx, ecx

lm_len:
    cmp BYTE PTR [edi + ecx], 0
    je lm_len_done
    inc ecx
    jmp lm_len

lm_len_done:
    mov fLen, ecx
    test ecx, ecx
    jz lm_no

    mov esi, pLine

lm_find:
    mov al, [esi]
    test al, al
    jz lm_use_start

    cmp al, CHAR_PIPE
    je lm_after_pipe

    inc esi
    jmp lm_find

lm_after_pipe:
    inc esi
    mov fieldStart, esi
    jmp lm_compare

lm_use_start:
    mov esi, pLine
    mov fieldStart, esi

lm_compare:
    mov edi, OFFSET accFilter
    mov ecx, fLen
    push esi
    cld
    repe cmpsb
    pop esi
    jne lm_no

    mov edx, fieldStart
    add edx, fLen

    mov al, [edx]

    cmp al, CHAR_PIPE
    je lm_yes

    cmp al, CHAR_SPACE
    je lm_yes

    test al, al
    jz lm_yes

lm_no:
    xor eax, eax
    ret

lm_yes:
    mov eax, 1
    ret

LineMatchesAccount ENDP

CopyStatementLine PROC USES esi edi ecx, pLine:DWORD, pDest:DWORD
    mov esi, pLine
    mov edi, pDest
    xor ecx, ecx

csl_loop:
    mov al, [esi]
    test al, al
    jz csl_done

    cmp al, CHAR_CR
    je csl_done

    cmp al, CHAR_LF
    je csl_done

    cmp ecx, STMT_LINE_LEN - 1
    jae csl_done

    mov [edi], al
    inc esi
    inc edi
    inc ecx
    jmp csl_loop

csl_done:
    mov BYTE PTR [edi], 0
    ret
CopyStatementLine ENDP

; =============================================================================
; ADMIN OPERATIONS
; =============================================================================

DoCreateAccount PROC
LOCAL newAccNo:DWORD
LOCAL newBal:DWORD
LOCAL pAcc:DWORD

    call Clrscr

    INVOKE SetColorUI, COLOR_HEADER
    mov edx, OFFSET lineBorder
    call WriteString
    call Crlf

    mov eax, dbHeader.accountCount
    cmp eax, MAX_ACCOUNTS
    jae adm_db_full

    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, OFFSET strNewAccPrompt
    call WriteString
    call ReadDec
    mov newAccNo, eax
    call Crlf

    test eax, eax
    jz adm_invalid

    cmp newAccNo, ADMIN_ACC_NO
    je adm_invalid

    mov ebx, newAccNo
    call FindAccount
    cmp eax, -1
    jne adm_acc_exists

    INVOKE ReadAmount, OFFSET strNewBalPrompt, ADDR newBal
    cmp eax, OK
    jne adm_invalid

    mov eax, dbHeader.accountCount
    mov ebx, SIZEOF ACCOUNT
    mul ebx
    lea esi, [accounts + eax]
    mov pAcc, esi

    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, OFFSET strNewNamePrompt
    call WriteString

    lea edx, [esi].ACCOUNT.holderName
    mov ecx, NAME_LEN - 1
    call ReadString
    call Crlf

    mov edx, OFFSET strNewPinPrompt
    call WriteString

    INVOKE ReadMaskedPin, OFFSET rawPinBuffer, 4
    mov enteredPinLen, eax
    call Crlf

    cmp enteredPinLen, MIN_PIN_LEN
    jne adm_invalid_pin

    mov eax, newAccNo
    mov [esi].ACCOUNT.accNo, eax

    mov eax, newBal
    mov [esi].ACCOUNT.balance, eax

    mov [esi].ACCOUNT.status, 0
    mov [esi].ACCOUNT.failCount, 0
    mov [esi].ACCOUNT.dailyWithdrawn, 0
    mov [esi].ACCOUNT.lastWdrDate, 0

    INVOKE GetTickCount
    mov ebx, newAccNo
    xor ebx, eax
    mov [esi].ACCOUNT.salt, ebx

    INVOKE HashPin, OFFSET rawPinBuffer, [esi].ACCOUNT.salt
    mov [esi].ACCOUNT.pinHash, eax

    inc dbHeader.accountCount

    call RebuildIndex
    call SaveAccounts
    call WipePinBuffers

    INVOKE ShowMessageBox, OFFSET strAccCreated
    ret

adm_invalid_pin:
    call WipePinBuffers
    INVOKE ShowMessageBox, OFFSET strShortPin
    ret

adm_invalid:
    INVOKE ShowMessageBox, OFFSET strInvalidInput
    ret

adm_db_full:
    INVOKE SetColorUI, COLOR_ERROR
    mov edx, OFFSET strDbFull
    call WriteString
    call Crlf
    call WaitMsg
    ret

adm_acc_exists:
    INVOKE SetColorUI, COLOR_ERROR
    mov edx, OFFSET strAccExists
    call WriteString
    call Crlf
    call WaitMsg
    ret

DoCreateAccount ENDP

DoUnlockAccount PROC
    call Clrscr

    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, OFFSET strUnlockPrompt
    call WriteString
    call ReadDec
    call Crlf

    mov ebx, eax
    call FindAccount
    cmp eax, -1
    je adm_unl_notfound

    mov ebx, SIZEOF ACCOUNT
    mul ebx
    lea esi, [accounts + eax]

    mov [esi].ACCOUNT.status, 0
    mov [esi].ACCOUNT.failCount, 0

    call SaveAccounts

    INVOKE ShowMessageBox, OFFSET strUnlockedMsg
    ret

adm_unl_notfound:
    INVOKE SetColorUI, COLOR_ERROR
    mov edx, OFFSET strErrTarget
    call WriteString
    call Crlf
    call WaitMsg
    ret

DoUnlockAccount ENDP

DoListAccounts PROC
LOCAL idx:DWORD

    call Clrscr

    INVOKE SetColorUI, COLOR_HEADER
    mov edx, OFFSET lineBorder
    call WriteString
    call Crlf

    mov idx, 0

adm_list_loop:
    mov eax, idx
    cmp eax, dbHeader.accountCount
    jae adm_list_done

    mov ebx, SIZEOF ACCOUNT
    mul ebx
    lea esi, [accounts + eax]

    INVOKE SetColorUI, COLOR_PROMPT

    mov eax, [esi].ACCOUNT.accNo
    call WriteDec

    mov al, CHAR_SPACE
    call WriteChar
    mov al, CHAR_PIPE
    call WriteChar
    mov al, CHAR_SPACE
    call WriteChar

    INVOKE SetColorUI, COLOR_DEFAULT
    lea edx, [esi].ACCOUNT.holderName
    call WriteString

    mov al, CHAR_SPACE
    call WriteChar
    mov al, CHAR_PIPE
    call WriteChar
    mov al, CHAR_SPACE
    call WriteChar

    INVOKE SetColorUI, COLOR_SUCCESS
    mov edx, OFFSET strPKR
    call WriteString

    mov eax, [esi].ACCOUNT.balance
    call WriteDec

    mov al, CHAR_SPACE
    call WriteChar
    mov al, CHAR_PIPE
    call WriteChar
    mov al, CHAR_SPACE
    call WriteChar

    test [esi].ACCOUNT.status, 1
    jnz adm_disp_locked

    INVOKE SetColorUI, COLOR_SUCCESS
    mov al, 'A'
    call WriteChar
    jmp adm_list_next

adm_disp_locked:
    INVOKE SetColorUI, COLOR_ERROR
    mov al, 'L'
    call WriteChar

adm_list_next:
    call Crlf

    inc idx
    jmp adm_list_loop

adm_list_done:
    call Crlf
    call WaitMsg
    ret

DoListAccounts ENDP

DoVaultStatus PROC
LOCAL idx:DWORD
LOCAL row:DWORD
LOCAL totalCash:DWORD

    call Clrscr

    INVOKE SetColorUI, COLOR_HEADER
    mov edx, OFFSET strVaultTitle
    call WriteString
    call Crlf

    mov edx, OFFSET lineBorder
    call WriteString
    call Crlf

    mov idx, 0

vs_loop:
    mov eax, idx
    cmp eax, DENOM_COUNT
    jae vs_total

    imul eax, eax, VAULT_COLS * 4
    mov row, eax

    INVOKE SetColorUI, COLOR_PROMPT

    mov edx, OFFSET strPKR
    call WriteString

    mov eax, row
    mov eax, vaultTable[eax + COL_VALUE * 4]
    call WriteDec

    mov edx, OFFSET strNoteDisp
    call WriteString

    mov edx, OFFSET strStockLabel
    call WriteString

    mov eax, row
    mov eax, vaultTable[eax + COL_STOCK * 4]
    call WriteDec

    call Crlf

    inc idx
    jmp vs_loop

vs_total:
    mov totalCash, 0
    mov idx, 0

vs_total_loop:
    mov eax, idx
    cmp eax, DENOM_COUNT
    jae vs_total_done

    imul eax, eax, VAULT_COLS * 4
    mov row, eax

    mov eax, vaultTable[row + COL_VALUE * 4]
    mov ebx, vaultTable[row + COL_STOCK * 4]
    mul ebx

    add totalCash, eax

    inc idx
    jmp vs_total_loop

vs_total_done:
    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, OFFSET strTotalVault
    call WriteString

    INVOKE SetColorUI, COLOR_SUCCESS
    mov eax, totalCash
    call WriteDec
    call Crlf
    call Crlf

    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, OFFSET strTotalTxVol
    call WriteString

    INVOKE UInt64ToStr, dbHeader.totalTxHigh, dbHeader.totalTxLow, OFFSET logBuffer

    INVOKE SetColorUI, COLOR_TITLE
    mov edx, OFFSET logBuffer
    call WriteString
    call Crlf
    call Crlf

    call WaitMsg
    ret

DoVaultStatus ENDP

; =============================================================================
; FILE PERSISTENCE
; =============================================================================

LoadOrCreateAccounts PROC
LOCAL expected:DWORD

    mov edx, OFFSET fnAccounts
    call OpenInputFile
    cmp eax, INVALID_HANDLE_VALUE
    je CreateDefaults

    mov ebx, eax

    mov eax, ebx
    mov edx, OFFSET dbHeader
    mov ecx, SIZEOF FILE_HEADER
    call ReadFromFile
    jc loc_fatal

    cmp eax, SIZEOF FILE_HEADER
    jne loc_fatal

    cmp dbHeader.magic, FILE_MAGIC
    jne loc_fatal

    cmp dbHeader.version, 2
    jne loc_fatal

    cmp dbHeader.accountCount, MAX_ACCOUNTS
    ja loc_fatal

    mov eax, SIZEOF ACCOUNT
    imul eax, dbHeader.accountCount
    mov expected, eax

    cmp expected, 0
    je loc_skip_read

    mov eax, ebx
    mov edx, OFFSET accounts
    mov ecx, expected
    call ReadFromFile
    jc loc_fatal

    cmp eax, expected
    jne loc_fatal

loc_skip_read:
    mov eax, ebx
    call CloseFile

    call RebuildIndex

    call ComputeChecksum
    cmp eax, dbHeader.checksum
    je loc_done

loc_fatal:
    INVOKE SetColorUI, COLOR_ERROR
    mov edx, OFFSET strErrChecksum
    call WriteString
    call Crlf
    call WaitMsg
    exit

loc_done:
    ret

CreateDefaults:
    mov dbHeader.magic, FILE_MAGIC
    mov dbHeader.version, 2
    mov dbHeader.accountCount, 3
    mov dbHeader.txIdCounter, 10000
    mov dbHeader.totalTxLow, 0
    mov dbHeader.totalTxHigh, 0
    mov dbHeader.adminSalt, 0
    mov dbHeader.adminPinHash, 0

    mov accounts[0*SIZEOF ACCOUNT].ACCOUNT.accNo, 10010001
    mov accounts[0*SIZEOF ACCOUNT].ACCOUNT.salt, 778899h
    mov accounts[0*SIZEOF ACCOUNT].ACCOUNT.balance, 50000
    mov accounts[0*SIZEOF ACCOUNT].ACCOUNT.status, 0
    mov accounts[0*SIZEOF ACCOUNT].ACCOUNT.failCount, 0
    mov accounts[0*SIZEOF ACCOUNT].ACCOUNT.dailyWithdrawn, 0
    mov accounts[0*SIZEOF ACCOUNT].ACCOUNT.lastWdrDate, 0

    INVOKE HashPin, OFFSET strPin1, accounts[0*SIZEOF ACCOUNT].ACCOUNT.salt
    mov accounts[0*SIZEOF ACCOUNT].ACCOUNT.pinHash, eax

    mov accounts[1*SIZEOF ACCOUNT].ACCOUNT.accNo, 10020002
    mov accounts[1*SIZEOF ACCOUNT].ACCOUNT.salt, 112233h
    mov accounts[1*SIZEOF ACCOUNT].ACCOUNT.balance, 25000
    mov accounts[1*SIZEOF ACCOUNT].ACCOUNT.status, 0
    mov accounts[1*SIZEOF ACCOUNT].ACCOUNT.failCount, 0
    mov accounts[1*SIZEOF ACCOUNT].ACCOUNT.dailyWithdrawn, 0
    mov accounts[1*SIZEOF ACCOUNT].ACCOUNT.lastWdrDate, 0

    INVOKE HashPin, OFFSET strPin2, accounts[1*SIZEOF ACCOUNT].ACCOUNT.salt
    mov accounts[1*SIZEOF ACCOUNT].ACCOUNT.pinHash, eax

    mov accounts[2*SIZEOF ACCOUNT].ACCOUNT.accNo, 10030003
    mov accounts[2*SIZEOF ACCOUNT].ACCOUNT.salt, 445566h
    mov accounts[2*SIZEOF ACCOUNT].ACCOUNT.balance, 100000
    mov accounts[2*SIZEOF ACCOUNT].ACCOUNT.status, 0
    mov accounts[2*SIZEOF ACCOUNT].ACCOUNT.failCount, 0
    mov accounts[2*SIZEOF ACCOUNT].ACCOUNT.dailyWithdrawn, 0
    mov accounts[2*SIZEOF ACCOUNT].ACCOUNT.lastWdrDate, 0

    INVOKE HashPin, OFFSET strPin3, accounts[2*SIZEOF ACCOUNT].ACCOUNT.salt
    mov accounts[2*SIZEOF ACCOUNT].ACCOUNT.pinHash, eax

    call RebuildIndex
    call SaveAccounts
    ret

LoadOrCreateAccounts ENDP

SaveAccounts PROC USES ebx ecx edx esi edi
    call ComputeChecksum
    mov dbHeader.checksum, eax

    mov edx, OFFSET fnAccounts
    call CreateOutputFile
    cmp eax, INVALID_HANDLE_VALUE
    je sa_fail

    mov ebx, eax

    mov eax, ebx
    mov edx, OFFSET dbHeader
    mov ecx, SIZEOF FILE_HEADER
    call WriteToFile
    jc sa_fail

    mov eax, ebx
    mov edx, OFFSET accounts
    mov ecx, SIZEOF ACCOUNT
    imul ecx, dbHeader.accountCount
    call WriteToFile
    jc sa_fail

    mov eax, ebx
    call CloseFile

    mov eax, OK
    ret

sa_fail:
    mov eax, E_FILE
    ret

SaveAccounts ENDP

; =============================================================================
; ADMIN PIN SETUP AND SESSION TIMEOUT
; =============================================================================

EnsureAdminPin PROC
    cmp dbHeader.adminPinHash, 0
    jne eap_done

    call Clrscr

    INVOKE SetColorUI, COLOR_HEADER
    mov edx, OFFSET lineBorder
    call WriteString
    call Crlf

    mov edx, OFFSET strAdminHeader
    call WriteString
    call Crlf

    mov edx, OFFSET lineBorder
    call WriteString
    call Crlf

eap_retry:
    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, OFFSET strAdminSetPin
    call WriteString

    INVOKE ReadMaskedPin, OFFSET rawPinBuffer, 4
    mov enteredPinLen, eax
    call Crlf

    cmp enteredPinLen, MIN_PIN_LEN
    jne eap_retry

    INVOKE SetColorUI, COLOR_PROMPT
    mov edx, OFFSET strAdminCnfPin
    call WriteString

    INVOKE ReadMaskedPin, OFFSET pinConfirmBuf, 4
    mov enteredPinLen, eax
    call Crlf

    cmp enteredPinLen, MIN_PIN_LEN
    jne eap_retry

    mov esi, OFFSET rawPinBuffer
    mov edi, OFFSET pinConfirmBuf
    mov ecx, MIN_PIN_LEN
    cld
    repe cmpsb
    jne eap_mismatch

    INVOKE GetTickCount
    mov dbHeader.adminSalt, eax

    INVOKE HashPin, OFFSET rawPinBuffer, dbHeader.adminSalt
    mov dbHeader.adminPinHash, eax

    call SaveAccounts
    call WipePinBuffers
    jmp eap_done

eap_mismatch:
    call WipePinBuffers
    INVOKE ShowMessageBox, OFFSET strPinMismatch
    jmp eap_retry

eap_done:
    ret
EnsureAdminPin ENDP

CheckSessionTimeout PROC USES ebx
    INVOKE GetTickCount
    mov ebx, eax

    cmp lastActivity, 0
    je cst_ok

    sub ebx, lastActivity
    cmp ebx, SESSION_TIMEOUT_MS
    ja cst_timeout

cst_ok:
    mov eax, OK
    ret

cst_timeout:
    mov eax, E_TIMEOUT
    ret

CheckSessionTimeout ENDP

; =============================================================================
; SHOWMSGBOXASK CUSTOM DIALOG
; =============================================================================

ShowMsgBoxAsk PROC USES ecx, pText:DWORD, pCaption:DWORD, uType:DWORD
    call Clrscr

    INVOKE SetColorUI, COLOR_PROMPT
    INVOKE DrawBox, CONFIRM_LEFT, CONFIRM_TOP, CONFIRM_WIDTH, CONFIRM_HEIGHT

    INVOKE PrintCentered, pCaption, CONFIRM_LEFT, 7, CONFIRM_WIDTH

    INVOKE SetColorUI, COLOR_DEFAULT
    INVOKE PrintCentered, pText, CONFIRM_LEFT, 9, CONFIRM_WIDTH

    INVOKE SetCursor, 10, 11
    mov edx, OFFSET strYNPrompt
    call WriteString

mbr_retry:
    call ReadChar

    cmp al, 'Y'
    je mbr_yes

    cmp al, 'y'
    je mbr_yes

    cmp al, 'N'
    je mbr_no

    cmp al, 'n'
    je mbr_no

    jmp mbr_retry

mbr_yes:
    mov eax, IDYES
    ret

mbr_no:
    mov eax, IDNO
    ret
ShowMsgBoxAsk ENDP

END main