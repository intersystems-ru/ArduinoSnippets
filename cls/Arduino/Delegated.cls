/// Delegated Authentication with Arduino.
/// Installation steps:<br>
/// 1. Connect arduino (and upload C code from Delegated.ino there)<br>
/// 2. Make this class visible in %SYS namespace (import there or map pckage)<br>
/// 3. Set SerialPort parameter to a correct value and recompile the class<br>
/// 4. Run <example>Do ##class(Arduino.Delegated).InitEncryption(Key, IV)</example>
/// 5. Write encrypted user credentials to RFID card  with SetCredentials<br>
/// 6. Import ZAUTHENTICATE into %SYS<br>
/// 7. Enable Delegated and password auth for relevant services and/or apps
Class Arduino.Delegated [ Abstract ]
{

/// Name of a serial port to which Arduino is connected
Parameter SerialPort As %String = "com3";

/// Creates managed encryption key.<br>
/// key - Input key material.
/// Key material 16, 24, or 32 characters long (on Unicode systems, with all character values < 256) is used directly.
/// Otherwise, Password-Based Key Derivation Function #2 (PBKDF2)
/// is used with HMAC-SHA-1,
/// no salt, and one iteration
/// to generate an AES key of the next larger valid size (up to 32 bytes).
/// (See RSA Laboratories Public-Key Cryptography Standards #5 for more information.)
/// <br><br>
/// IV - Initialization vector (optional).
/// If this argument is present it must be 16 characters long (on Unicode systems, with all character values < 256).
/// If this argument is omitted (or is an empty string), a null initialization vector is used.
/// <br>
/// <example>Do ##class(Arduino.Delegated).Init("", "")</example>
ClassMethod Init(Key As %String, IV As %String)
{
	New $Namespace
	Set $Namespace = "%SYS"
	Set ^Arduino("Key")= Key
	Set ^Arduino("IV")= IV
}

/// Send Arduino the command to set credentials on a card to Username/Password (encrypted)
/// <example>Do ##class(Arduino.Delegated).SetCredentials("_SYSTEM", "SYS")</example>
ClassMethod SetCredentials(Username As %String(MAXLEN=15), Password As %String(MAXLEN=15)) As %Status
{
	
	Set Status = $$$OK
	
	Set CipherUsername = ..EncryptText(Username)
	Set CipherPassword = ..EncryptText(Password)
	
	Set User1 = $Extract(CipherUsername, 1, 16)
	
	Set User2 = $Extract(CipherUsername, 17, 32)
	Set User2 = ..AppendToString(User2, , 16)
	
	Set Pass1 = $Extract(CipherPassword, 1, 16)
	
	Set Pass2 = $Extract(CipherPassword, 17, 32)
	Set Pass2 = ..AppendToString(Pass2, , 16)
	
	Set CommandList = $ListBuild("Set", User1, User2, Pass1, Pass2)
	Set Command = $ListToString(CommandList, "@")

	Set Status = ..ExecuteCommand(.Command)
	If (Status = "Done") {
		Set Status = $$$OK
	} Else {
		Set Status = $$$ERROR($$$GeneralError, "SetCredentials failure, received: " _ Status) 
	}
	
	Return Status
}

/// Connect to an Arduino device, receive credentials, decode them and set to Username/Password variables.
/// <example>do ##class(Arduino.Delegated).GetCredentials(.Username, .Password)</example>
ClassMethod GetCredentials(Output Username As %String, Output Password As %String) As %Status
{
	Kill Username, Password
	Set Username = ""
	Set Password = ""
	Set Status = $$$OK
	
	Set Credentials = ..ExecuteCommand("Get")
	If (($L(Credentials) =65) && ($L(Credentials,"@") = 2)) {
		Set CipherUsername = $Piece(Credentials, "@", 1)
		Set CipherPassword = $Piece(Credentials, "@", 2)
		Set CipherUsername = $Extract(CipherUsername, 1, 24) // we need only first 24 characters
		Set CipherPassword = $Extract(CipherPassword, 1, 24)
		Set Username = ..DecryptText(CipherUsername)
		Set Password = ..DecryptText(CipherPassword)
	} Else {
		Set Status = $$$ERROR($$$GeneralError, "GetCredentials failure, received: " _ Credentials) 
	}
	
	Return Status
}

/// Send one line at a time, using common terminating characters (i.e., CR) and receive output
/// Possible comands:<br>
/// <b>Get</b> - reads an RFID card and returns information in a format: user@pass<br>
/// <b>Set@user1@user2@pass1@pass2</b> - sets information on a RFID card 
/// in a format: user@pass (where user = user1@user2)<br>
/// Returns output, produced by Arduino
/// <example>w ##class(Arduino.Delegated).ExecuteCommand("Get")</example>
ClassMethod ExecuteCommand(ByRef Command As %String, SerialPort = {..#SerialPort}) As %String
{
	set x=""
	try {
        //Parameters used to open the serial device:
        //  portstate = " 0801n0" - by byte position:
        //      1: space indicates "don't disconnect the port"
        //      2: 0 indicates "don't use modem control"
        //      3: 8 indicates 8 data bits
        //      4: 0 indicates no parity
        //      5: 1 indicates one stop bit
        //      6: n indicates that flow control is disabled
        //      7: 0 indicates disable DTR
        //  /BAUD=9600 determines the baud rate, of course.
        open SerialPort:(:::" 0801n0":/BAUD=9600)
        set old = $io //Keep track of the original device
        use SerialPort

		write $char(10)
		
        hang 1
        
        write Command _ $Char(10)
        
        read x //Read until a termination character is reached
        use old
        close SerialPort       
    } catch ex {
        close SerialPort
        w $System.Status.GetErrorText(ex.AsStatus())
    }
    
    return x
}

/// Get key to encode/decode via EncryptText/DecryptText
ClassMethod GetKey() [ CodeMode = expression ]
{
$Get(^Arduino("Key"))
}

/// Get IV to encode/decode via EncryptText/DecryptText
ClassMethod GetIV() [ CodeMode = expression ]
{
$Get(^Arduino("IV"))
}

/// Encrypt PlainText with AESCBCEncrypt
/// <example>Write ##class(Arduino.Delegated).EncryptText("string")</example>
ClassMethod EncryptText(PlainText As %String) As %String
{
	
	Set Text=$ZConvert(PlainText,"O","UTF8")
	Set Text=$System.Encryption.AESCBCEncrypt(Text, ..GetKey(), ..GetIV())
	Set Ciphertext=$System.Encryption.Base64Encode(Text)
	Return Ciphertext
}

/// Decrypt PlainText with AESCBCEncrypt
/// <example>Write ##class(Arduino.Delegated).DecryptText("sFgKzZVle187N4OqhhcXPw==")</example>
ClassMethod DecryptText(CipherText As %String) As %String
{
	Set Text=$System.Encryption.Base64Decode(CipherText)
	Set Text=$System.Encryption.AESCBCDecrypt(Text, ..GetKey(), ..GetIV())
	Set PlainText=$ZConvert(Text,"I","UTF8") 
	Return PlainText
}

/// Extends right side of a String by Character up to Length chars
/// <example>Write ##class(Arduino.Delegated).AppendToString("")</example>
ClassMethod AppendToString(String As %String, Character As %String(MAXLEN=1) = "_", Length As %Integer = {$Length(String)}) As %String
{
	Set Difference = Length - $Length(String)  
	Return:Difference<=0 String
	Set Tail = $Justify("", Difference)
	Set Tail = $Translate(Tail, " ", Character)
	Return String _ Tail
}

}

