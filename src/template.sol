// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

/////////////
// Imports //
/////////////

////////////////
// Interfaces //
////////////////

//////////////
// Liraries //
//////////////

///////////////
// Contracts //
///////////////

/*
    * @title name
    * @author author_name 
    * @dev description
*/

contract ContractName {
    ////////////
    // Errors //
    ////////////

    /**
     * @notice it is preffered to use error codes as it is more gas efficient
     * @notice write the contract name at the beginning of the error message
     * @custom:example "error ContractName__AmountMustBeGreaterThanZero();"
     */

    ///////////
    // Types //
    ///////////

    /////////////////////
    // State Variables //
    /////////////////////

    /**
     * @notice immutables then constants then state variables
     * @notice write the name of immuatable as i_variableName
     * @notice write the name of constant using CAPITAL letters as CONSTANT_NAME
     * @notice write the name of state variables as s_variableName
     */

    ////////////
    // Events //
    ////////////

    /**
     * @notice indexed keyword can be added only up to 3 parameters
     * @custom:example "event ExampleEvent(address indexed _address, uint256 _amount);"
     */

    ///////////////
    // Modifiers //
    ///////////////

    ///////////////
    // Functions //
    ///////////////

    /**
     * @notice Remember to Follow CEI pattern which is Checks, Effects, Interactions
     * checks: validate the inputs
     * effects: update the state variables
     * interactions: interact with other contracts or other functions
     * @notice Write the function name in camelCase
     */

    /////////////////
    // Constructor //
    /////////////////

    constructor() {}

    /*
    Which function is called, fallback() or receive()?

           send Ether
               |
         msg.data is empty?
              / \
            yes  no
            /     \
    receive() exists?  fallback()
         /   \
        yes   no
        /      \
    receive()   fallback()

    */

    /////////////
    // recieve //
    /////////////

    receive() external payable {}

    //////////////
    // fallback //
    //////////////

    fallback() external payable {}

    ////////////////////////
    // External Functions //
    ////////////////////////

    /**
     * @notice External functions are part of the contract interface
     * which means they can be called from other contracts and via transactions.
     * @notice An external function f cannot be called internally (i.e. f() does not work, but this.f() works).
     */

    //////////////////////
    // Public Functions //
    //////////////////////

    /**
     * @notice Public functions are part of the contract interface and can be either called internally or via message calls.
     */

    ////////////////////////
    // Internal Functions //
    ////////////////////////

    /**
     * @notice Internal functions can only be accessed from within the current contract or contracts deriving from it.
     * They cannot be accessed externally.
     * @notice They are not exposed to the outside through the contract’s ABI.
     * @notice They can take parameters of internal types like mappings or storage references.
     */

    ///////////////////////
    // Private Functions //
    ///////////////////////

    /**
     * @notice Private functions are like internal ones but they are not visible in derived contracts.
     */

    //////////////////////////////////////////////
    // Internal & private view & pure Functions //
    //////////////////////////////////////////////

    /////////////////////////////////////////////
    // External & public view & pure Functions //
    /////////////////////////////////////////////

    /////////////
    // Getters //
    /////////////

    /**
     * @notice Getters are functions that return the value of state variables.
     * @notice state variables are more gas efficient when set to private so it is preffered to use getters to access them
     */
}
